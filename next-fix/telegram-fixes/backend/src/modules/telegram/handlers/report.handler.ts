import { Injectable, Logger } from '@nestjs/common';
import { Employee } from '@prisma/client';
import { Bot, Context, InlineKeyboard } from 'grammy';
import { PrismaService } from '../../../prisma/prisma.service';
import { WorkLogsService } from '../../work-logs/work-logs.service';
import { money, texts } from '../bot-texts';
import { Session, TelegramSessionService } from '../telegram-session.service';
import { EmployeeGuard, isRateNotFoundError, mainMenu, showMenu } from '../telegram.utils';

/** Верхняя граница, за которой количество почти наверняка опечатка. */
const MAX_QUANTITY = 10_000;

/**
 * Основной сценарий: рабочий сообщает, что он сделал.
 *
 * Путь через кнопки — модель → операция → количество, плюс быстрый текстовый
 * ввод «Sport-12 24» для тех, кому кнопки уже медленны. Здесь же отмена
 * только что созданной записи.
 */
@Injectable()
export class ReportHandler {
  private readonly logger = new Logger(ReportHandler.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly workLogs: WorkLogsService,
    private readonly sessions: TelegramSessionService,
  ) {}

  register(bot: Bot, guard: EmployeeGuard): void {
    bot.command('report', (ctx) => guard(ctx, (e) => this.startReport(ctx, e)));

    bot.callbackQuery('report', (ctx) => guard(ctx, (e) => this.startReport(ctx, e)));
    bot.callbackQuery('all', (ctx) => guard(ctx, (e) => this.askProduct(ctx, e, true)));
    bot.callbackQuery('cancel', (ctx) => guard(ctx, () => this.onCancel(ctx)));

    bot.callbackQuery(/^p:(.+)$/, (ctx) =>
      guard(ctx, (e) => this.onProductChosen(ctx, e, ctx.match[1])),
    );
    bot.callbackQuery(/^o:(.+)$/, (ctx) =>
      guard(ctx, (e) => this.onOperationChosen(ctx, e, ctx.match[1])),
    );
    bot.callbackQuery(/^undo:(.+)$/, (ctx) =>
      guard(ctx, (e) => this.onUndo(ctx, e, ctx.match[1])),
    );

    // Свободный текст: либо ожидаемое количество, либо быстрый ввод,
    // либо ничего из этого — тогда показываем меню.
    bot.on('message:text', (ctx) => this.onText(ctx, guard));
  }

  // ── Шаги мастера ─────────────────────────────────────────────────────────

  private async startReport(ctx: Context, employee: Employee): Promise<void> {
    this.sessions.clear(ctx.from!.id);
    await this.askProduct(ctx, employee, false);
  }

  /**
   * Список моделей. По умолчанию — те, по которым рабочий отчитывался
   * недавно: в цехе он неделями делает одну и ту же модель, и листать
   * полный справочник каждый раз незачем.
   */
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

  private async onProductChosen(
    ctx: Context,
    employee: Employee,
    productId: string,
  ): Promise<void> {
    const session = this.sessions.get(ctx.from!.id);
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
    _employee: Employee,
    operationId: string,
  ): Promise<void> {
    const session = this.sessions.get(ctx.from!.id);
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

  // ── Свободный текст ──────────────────────────────────────────────────────

  private async onText(ctx: Context, guard: EmployeeGuard): Promise<void> {
    const text = ctx.message?.text?.trim();

    // Команды обрабатываются своими хендлерами — сюда они долетают следом.
    if (!text || text.startsWith('/')) return;

    await guard(ctx, async (employee) => {
      const session = this.sessions.get(ctx.from!.id);

      if (session.step === 'awaiting_quantity') {
        await this.onQuantityEntered(ctx, employee, text, session);
        return;
      }

      // Быстрый ввод «Sport-12 24» — модель и количество одной строкой.
      const match = text.match(/^(.+?)\s+(\d+)$/);
      if (match) {
        await this.quickReport(ctx, employee, match[1].trim(), Number(match[2]));
        return;
      }

      await showMenu(ctx, employee);
    });
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

    // Сессия протухла между выбором модели и вводом числа — начинаем сначала,
    // чтобы не записать выработку по угаданным полям.
    if (!session.productId || !session.operationId) {
      await this.startReport(ctx, employee);
      return;
    }

    await this.saveReport(ctx, employee, session.productId, session.operationId, quantity);
    this.sessions.clear(ctx.from!.id);
  }

  /** Быстрый ввод: ищем модель по артикулу или названию. */
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

  // ── Запись и отмена ──────────────────────────────────────────────────────

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
      if (isRateNotFoundError(error)) {
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

  private async onCancel(ctx: Context): Promise<void> {
    this.sessions.clear(ctx.from!.id);
    await ctx.reply(texts.cancelled, { reply_markup: mainMenu() });
  }
}
