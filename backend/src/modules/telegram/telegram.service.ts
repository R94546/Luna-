import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Employee } from '@prisma/client';
import { Bot, Context } from 'grammy';
import { Update } from 'grammy/types';
import { PrismaService } from '../../prisma/prisma.service';
import { runWithTenant } from '../../prisma/tenant-context';
import { texts } from './bot-texts';
import { ReportHandler } from './handlers/report.handler';
import { StartHandler } from './handlers/start.handler';
import { SummaryHandler } from './handlers/summary.handler';
import { EmployeeGuard } from './telegram.utils';

const RATE_LIMIT_PER_MIN = 30;

/**
 * Оркестрация Telegram-бота.
 *
 * Здесь только то, что общее для всех сценариев: жизненный цикл бота,
 * приём апдейтов с идемпотентностью, авторизация рабочего и вход в
 * tenant-контекст. Сами сценарии живут в handlers/ — сервис их не знает
 * в подробностях, а лишь передаёт им бота и guard.
 */
@Injectable()
export class TelegramService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelegramService.name);
  private bot?: Bot;

  private readonly rateLimits = new Map<number, { count: number; resetAt: number }>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly startHandler: StartHandler,
    private readonly reportHandler: ReportHandler,
    private readonly summaryHandler: SummaryHandler,
  ) {}

  async onModuleInit(): Promise<void> {
    const token = this.config.get<string>('TELEGRAM_BOT_TOKEN', '');

    if (!token) {
      this.logger.warn('TELEGRAM_BOT_TOKEN не задан — бот не запущен');
      return;
    }

    this.bot = new Bot(token);
    this.registerHandlers(this.bot);

    const webhookUrl = this.config.get<string>('TELEGRAM_WEBHOOK_URL', '');

    if (webhookUrl) {
      const secret = this.config.get<string>('TELEGRAM_WEBHOOK_SECRET', '');
      await this.bot.api.setWebhook(`${webhookUrl}/api/v1/telegram/webhook/${secret}`, {
        secret_token: secret || undefined,
      });
      await this.bot.init();
      this.logger.log('Бот работает в режиме webhook');
    } else {
      // Polling только для разработки: при нескольких инстансах апдейты
      // начнут расходиться по процессам случайным образом.
      void this.bot.start({ onStart: () => this.logger.log('Бот работает в режиме polling') });
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.bot?.stop();
  }

  /**
   * Приём апдейта из вебхука.
   *
   * Идемпотентность обеспечивается таблицей telegram_updates: Telegram
   * повторяет доставку, если не получил 200 вовремя, и без этой проверки
   * один отчёт «24 juft» записался бы дважды.
   *
   * Обработка синхронная, без очереди: сценарий — три-четыре запроса к БД,
   * это единицы миллисекунд при таймауте Telegram в 60 секунд. Очередь
   * здесь добавила бы воркер, сериализацию и отдельный мониторинг, не решая
   * ни одной существующей проблемы — дубликаты и так закрыты идемпотентностью.
   */
  async handleUpdate(update: Update): Promise<void> {
    if (!this.bot) return;

    // createMany + skipDuplicates вместо create в try/catch: тот же один
    // запрос, но повтор не порождает исключение и не сорит `prisma:error`
    // в логах при каждом штатном ретрае Telegram.
    const { count } = await this.prisma.telegramUpdate.createMany({
      data: [{ updateId: BigInt(update.update_id) }],
      skipDuplicates: true,
    });

    if (count === 0) {
      this.logger.debug(`Апдейт ${update.update_id} уже обработан — пропуск`);
      return;
    }

    await this.bot.handleUpdate(update);
  }

  /**
   * Порядок регистрации значим.
   *
   * Первым идёт снятие «часиков» с нажатой кнопки — общий шаг для всех
   * callback'ов, поэтому его не должен повторять каждый обработчик.
   * Обработчик свободного текста внутри ReportHandler регистрируется
   * последним из всего, что реагирует на сообщения, и служит fallback'ом.
   */
  private registerHandlers(bot: Bot): void {
    const guard: EmployeeGuard = (ctx, fn) => this.withEmployee(ctx, fn);

    bot.on('callback_query:data', async (ctx, next) => {
      await ctx.answerCallbackQuery();
      await next();
    });

    this.startHandler.register(bot, guard);
    this.summaryHandler.register(bot, guard);
    this.reportHandler.register(bot, guard);

    bot.catch((err) => {
      this.logger.error(
        `Ошибка бота: ${err.message}`,
        err.error instanceof Error ? err.error.stack : undefined,
      );
    });
  }

  /**
   * Авторизация рабочего.
   *
   * Единственный признак — telegram_user_id. Незнакомому отправителю бот
   * не сообщает ни названия компании, ни списка моделей: по ответу бота
   * не должно быть видно, существует ли вообще такая система.
   *
   * Дальше работа идёт в tenant-контексте компании сотрудника — без него
   * Prisma-middleware не смог бы отфильтровать данные по арендатору.
   */
  private async withEmployee(
    ctx: Context,
    fn: (employee: Employee) => Promise<void>,
  ): Promise<void> {
    const tgId = ctx.from?.id;
    if (!tgId) return;

    if (!this.checkRateLimit(tgId)) {
      this.logger.warn(`Превышен лимит сообщений от Telegram ID ${tgId}`);
      return;
    }

    const employee = await this.prisma.employee.findFirst({
      where: { telegramUserId: BigInt(tgId), isActive: true, deletedAt: null },
    });

    if (!employee) {
      await ctx.reply(texts.unknownUser);
      return;
    }

    await runWithTenant({ companyId: employee.companyId }, () => fn(employee));
  }

  private checkRateLimit(tgId: number): boolean {
    const now = Date.now();
    const entry = this.rateLimits.get(tgId);

    if (!entry || now > entry.resetAt) {
      this.rateLimits.set(tgId, { count: 1, resetAt: now + 60_000 });
      return true;
    }

    entry.count += 1;
    return entry.count <= RATE_LIMIT_PER_MIN;
  }
}
