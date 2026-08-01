import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Employee } from '@prisma/client';
import { Bot, Context, InlineKeyboard } from 'grammy';
import { Update } from 'grammy/types';
import { PrismaService } from '../../prisma/prisma.service';
import { runWithTenant } from '../../prisma/tenant-context';
import { PieceRatesService } from '../piece-rates/piece-rates.service';
import { WorkLogsService } from '../work-logs/work-logs.service';
import { money, texts } from './bot-texts';

/** Шаг диалога. Между сообщениями бот помнит, чего он ждёт от рабочего. */
type Step = 'idle' | 'awaiting_quantity';

interface Session {
  step: Step;
  productId?: string;
  operationId?: string;
  updatedAt: number;
}

const SESSION_TTL_MS = 30 * 60_000;
const RATE_LIMIT_PER_MIN = 30;
const MAX_QUANTITY = 10_000;

@Injectable()
export class TelegramService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelegramService.name);
  private bot?: Bot;

  /**
   * Состояние диалогов в памяти процесса.
   *
   * Осознанное ограничение: при нескольких инстансах API рабочий,
   * попавший на другой инстанс, потеряет незавершённый шаг и начнёт заново.
   * Для одного инстанса (а это весь горизонт MVP) этого достаточно;
   * при масштабировании storage меняется на Redis без правки логики.
   */
  private readonly sessions = new Map<number, Session>();
  private readonly rateLimits = new Map<number, { count: number; resetAt: number }>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly workLogs: WorkLogsService,
    private readonly rates: PieceRatesService,
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

  // ── Обработчики ──────────────────────────────────────────────────────────

  private registerHandlers(bot: Bot): void {
    bot.command('start', (ctx) => this.onStart(ctx));
    bot.command('help', (ctx) => ctx.reply(texts.help));
    bot.command('report', (ctx) => this.withEmployee(ctx, (e) => this.startReport(ctx, e)));
    bot.command('today', (ctx) => this.withEmployee(ctx, (e) => this.showToday(ctx, e)));
    bot.command('month', (ctx) => this.withEmployee(ctx, (e) => this.showMonth(ctx, e)));

    bot.on('callback_query:data', (ctx) => this.onCallback(ctx));
    bot.on('message:text', (ctx) => this.onText(ctx));

    bot.catch((err) => {
      this.logger.error(`Ошибка бота: ${err.message}`, err.error instanceof Error ? err.error.stack : undefined);
    });
  }

  /** `/start` без кода — меню; с кодом — привязка аккаунта. */
  private async onStart(ctx: Context): Promise<void> {
    const code = ctx.match?.toString().trim().toUpperCase();
    const tgId = ctx.from?.id;
    if (!tgId) return;

    if (!code) {
      await this.withEmployee(ctx, (e) => this.showMenu(ctx, e));
      return;
    }

    const existing = await this.prisma.employee.findFirst({ where: { telegramUserId: BigInt(tgId) } });
    if (existing) {
      await ctx.reply(texts.linkCodeTaken);
      return;
    }

    const link = await this.prisma.telegramLinkCode.findFirst({
      where: { code },
      include: { employee: true },
    });

    if (!link || link.expiresAt < new Date()) {
      await ctx.reply(texts.linkInvalid);
      return;
    }

    if (link.usedAt) {
      await ctx.reply(texts.linkAlreadyUsed);
      return;
    }

    await this.prisma.$transaction([
      this.prisma.telegramLinkCode.update({
        where: { id: link.id },
        data: { usedAt: new Date() },
      }),
      this.prisma.employee.update({
        where: { id: link.employeeId },
        data: {
          telegramUserId: BigInt(tgId),
          telegramUsername: ctx.from?.username,
          telegramLinkedAt: new Date(),
        },
      }),
    ]);

    this.logger.log(`Сотрудник ${link.employee.fullName} привязал Telegram`);

    await ctx.reply(texts.linkSuccess(link.employee.fullName), {
      reply_markup: this.mainMenu(),
    });
  }

  private async onCallback(ctx: Context): Promise<void> {
    const data = ctx.callbackQuery?.data ?? '';
    await ctx.answerCallbackQuery();

    await this.withEmployee(ctx, async (employee) => {
      const [action, value] = data.split(':');

      switch (action) {
        case 'menu':
          await this.showMenu(ctx, employee);
          break;
        case 'report':
          await this.startReport(ctx, employee);
          break;
        case 'today':
          await this.showToday(ctx, employee);
          break;
        case 'month':
          await this.showMonth(ctx, employee);
          break;
        case 'all':
          await this.askProduct(ctx, employee, true);
          break;
        case 'p':
          await this.onProductChosen(ctx, employee, value);
          break;
        case 'o':
          await this.onOperationChosen(ctx, employee, value);
          break;
        case 'undo':
          await this.onUndo(ctx, employee, value);
          break;
        case 'cancel':
          this.clearSession(ctx.from!.id);
          await ctx.reply(texts.cancelled, { reply_markup: this.mainMenu() });
          break;
      }
    });
  }

  private async onText(ctx: Context): Promise<void> {
    const text = ctx.message?.text?.trim();
    if (!text || text.startsWith('/')) return;

    await this.withEmployee(ctx, async (employee) => {
      const session = this.getSession(ctx.from!.id);

      if (session.step === 'awaiting_quantity') {
        await this.onQuantityEntered(ctx, employee, text, session);
        return;
      }

      // Быстрый ввод «Sport-12 24» — для тех, кому кнопки уже медленны.
      const match = text.match(/^(.+?)\s+(\d+)$/);
      if (match) {
        await this.quickReport(ctx, employee, match[1].trim(), Number(match[2]));
        return;
      }

      await this.showMenu(ctx, employee);
    });
  }

  // ── Сценарий отчёта ──────────────────────────────────────────────────────

  private async startReport(ctx: Context, employee: Employee): Promise<void> {
    this.clearSession(ctx.from!.id);
    await this.askProduct(ctx, employee, false);
  }

  private async askProduct(ctx: Context, employee: Employee, all: boolean): Promise<void> {
    const recent = all ? [] : await this.workLogs.recentProductsFor(employee.id);

    const products =
      recent.length > 0
        ? recent
        : await this.prisma.product.findMany({
            where: { isActive: true, deletedAt: null },
            select: { id: true, name: true, sku: true },
            orderBy: { name: 'asc' },
            take: 30,
          });

    if (products.length === 0) {
      await ctx.reply(texts.noProducts);
      return;
    }

    const kb = new InlineKeyboard();
    products.forEach((p) => kb.text(p.name, `p:${p.id}`).row());
    if (!all && recent.length > 0) kb.text(texts.btnMore, 'all').row();
    kb.text(texts.btnCancel, 'cancel');

    await ctx.reply(texts.askProduct, { reply_markup: kb });
  }

  private async onProductChosen(ctx: Context, employee: Employee, productId: string): Promise<void> {
    const session = this.getSession(ctx.from!.id);
    session.productId = productId;

    // У рабочего одна специализация — шаг выбора операции лишний.
    if (employee.defaultOperationId) {
      await this.onOperationChosen(ctx, employee, employee.defaultOperationId);
      return;
    }

    const operations = await this.prisma.operation.findMany({
      where: { isActive: true, deletedAt: null },
      orderBy: { sortOrder: 'asc' },
    });

    if (operations.length === 0) {
      await ctx.reply(texts.noOperations);
      return;
    }

    const kb = new InlineKeyboard();
    operations.forEach((o) => kb.text(o.name, `o:${o.id}`).row());
    kb.text(texts.btnCancel, 'cancel');

    await ctx.reply(texts.askOperation, { reply_markup: kb });
  }

  private async onOperationChosen(
    ctx: Context,
    employee: Employee,
    operationId: string,
  ): Promise<void> {
    const session = this.getSession(ctx.from!.id);
    session.operationId = operationId;
    session.step = 'awaiting_quantity';

    const [product, operation] = await Promise.all([
      this.prisma.product.findFirst({ where: { id: session.productId } }),
      this.prisma.operation.findFirst({ where: { id: operationId } }),
    ]);

    if (!product || !operation) {
      await ctx.reply(texts.genericError);
      return;
    }

    await ctx.reply(texts.askQuantity(product.name, operation.name));
  }

  private async onQuantityEntered(
    ctx: Context,
    employee: Employee,
    text: string,
    session: Session,
  ): Promise<void> {
    const quantity = Number(text.replace(/\s/g, ''));

    if (!Number.isInteger(quantity) || quantity <= 0) {
      await ctx.reply(texts.quantityInvalid);
      return;
    }

    if (quantity > MAX_QUANTITY) {
      await ctx.reply(texts.quantityTooLarge);
      return;
    }

    if (!session.productId || !session.operationId) {
      await this.startReport(ctx, employee);
      return;
    }

    await this.saveReport(ctx, employee, session.productId, session.operationId, quantity);
    this.clearSession(ctx.from!.id);
  }

  /** Быстрый ввод: ищем модель по названию или артикулу. */
  private async quickReport(
    ctx: Context,
    employee: Employee,
    query: string,
    quantity: number,
  ): Promise<void> {
    if (!employee.defaultOperationId) {
      await this.startReport(ctx, employee);
      return;
    }

    const product = await this.prisma.product.findFirst({
      where: {
        isActive: true,
        deletedAt: null,
        OR: [
          { sku: { equals: query, mode: 'insensitive' } },
          { name: { contains: query, mode: 'insensitive' } },
        ],
      },
    });

    if (!product) {
      await this.startReport(ctx, employee);
      return;
    }

    await this.saveReport(ctx, employee, product.id, employee.defaultOperationId, quantity);
  }

  private async saveReport(
    ctx: Context,
    employee: Employee,
    productId: string,
    operationId: string,
    quantity: number,
  ): Promise<void> {
    const operation = await this.prisma.operation.findFirst({ where: { id: operationId } });

    try {
      const log = await this.workLogs.createFromTelegram({
        companyId: employee.companyId,
        employeeId: employee.id,
        productId,
        operationId,
        quantity,
        telegramMsgId: ctx.message?.message_id,
      });

      const kb = new InlineKeyboard().text(texts.btnUndo, `undo:${log.id}`);

      await ctx.reply(
        texts.reportSaved({
          product: log.product.name,
          operation: log.operation.name,
          quantity,
          rate: money(log.rate),
          amount: money(log.amount),
          needsApproval: log.status === 'PENDING',
        }),
        { reply_markup: kb },
      );
    } catch (error) {
      // Самая частая причина — расценка не задана. Рабочий должен понять,
      // что делать, а не увидеть «ошибка сервера».
      if (this.isRateError(error)) {
        await ctx.reply(texts.noRate(operation?.name ?? ''));
        return;
      }

      this.logger.error(`Не удалось сохранить отчёт: ${String(error)}`);
      await ctx.reply(texts.genericError);
    }
  }

  private async onUndo(ctx: Context, employee: Employee, workLogId: string): Promise<void> {
    const removed = await this.workLogs.cancelByEmployee(workLogId, employee.id);
    await ctx.reply(removed ? texts.undoDone : texts.undoTooLate);
  }

  // ── Сводки ───────────────────────────────────────────────────────────────

  private async showToday(ctx: Context, employee: Employee): Promise<void> {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const summary = await this.workLogs.employeeSummary(employee.id, today, today);

    if (summary.totalQuantity === 0) {
      await ctx.reply(texts.todayEmpty, { reply_markup: this.mainMenu() });
      return;
    }

    const lines = [
      texts.todayTitle(summary.totalQuantity, money(summary.totalAmount)),
      '',
      ...summary.byProduct.map((b) => texts.byProductLine(b.name, b.quantity, money(b.amount))),
    ];

    await ctx.reply(lines.join('\n'), { reply_markup: this.mainMenu() });
  }

  private async showMonth(ctx: Context, employee: Employee): Promise<void> {
    const now = new Date();
    const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const to = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0));

    const summary = await this.workLogs.employeeSummary(employee.id, from, to);

    if (summary.totalQuantity === 0) {
      await ctx.reply(texts.monthEmpty, { reply_markup: this.mainMenu() });
      return;
    }

    const lines = [
      texts.monthTitle(summary.totalQuantity, money(summary.totalAmount)),
      '',
      ...summary.byProduct.map((b) => texts.byProductLine(b.name, b.quantity, money(b.amount))),
    ];

    await ctx.reply(lines.join('\n'), { reply_markup: this.mainMenu() });
  }

  private async showMenu(ctx: Context, employee: Employee): Promise<void> {
    await ctx.reply(texts.menu(employee.fullName), { reply_markup: this.mainMenu() });
  }

  private mainMenu(): InlineKeyboard {
    return new InlineKeyboard()
      .text(texts.btnReport, 'report')
      .row()
      .text(texts.btnToday, 'today')
      .text(texts.btnMonth, 'month');
  }

  // ── Инфраструктура ───────────────────────────────────────────────────────

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

  private getSession(tgId: number): Session {
    const existing = this.sessions.get(tgId);

    if (existing && Date.now() - existing.updatedAt < SESSION_TTL_MS) {
      existing.updatedAt = Date.now();
      return existing;
    }

    const fresh: Session = { step: 'idle', updatedAt: Date.now() };
    this.sessions.set(tgId, fresh);
    return fresh;
  }

  private clearSession(tgId: number): void {
    this.sessions.delete(tgId);
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

  private isRateError(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      (error as { code: unknown }).code === 'RATE_NOT_FOUND'
    );
  }
}
