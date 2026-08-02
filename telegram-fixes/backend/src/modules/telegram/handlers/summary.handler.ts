import { Injectable } from '@nestjs/common';
import { Employee } from '@prisma/client';
import { Bot, Context } from 'grammy';
import { WorkLogsService } from '../../work-logs/work-logs.service';
import { money, texts } from '../bot-texts';
import { EmployeeGuard, mainMenu } from '../telegram.utils';

/** Заголовок сводки: единственное, чем /today отличается от /month. */
type SummaryTexts = {
  title: (quantity: number, amount: string) => string;
  empty: string;
};

/**
 * Сводки рабочего: `/today` и `/month`.
 *
 * Обе команды — один и тот же вывод над разным диапазоном дат, поэтому
 * отличаются только границами периода и парой строк текста.
 */
@Injectable()
export class SummaryHandler {
  constructor(private readonly workLogs: WorkLogsService) {}

  register(bot: Bot, guard: EmployeeGuard): void {
    bot.command('today', (ctx) => guard(ctx, (e) => this.showToday(ctx, e)));
    bot.command('month', (ctx) => guard(ctx, (e) => this.showMonth(ctx, e)));

    bot.callbackQuery('today', (ctx) => guard(ctx, (e) => this.showToday(ctx, e)));
    bot.callbackQuery('month', (ctx) => guard(ctx, (e) => this.showMonth(ctx, e)));
  }

  private async showToday(ctx: Context, employee: Employee): Promise<void> {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    await this.reply(ctx, employee, today, today, {
      title: texts.todayTitle,
      empty: texts.todayEmpty,
    });
  }

  private async showMonth(ctx: Context, employee: Employee): Promise<void> {
    const now = new Date();
    const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    // Нулевой день следующего месяца — последний день текущего.
    const to = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0));

    await this.reply(ctx, employee, from, to, {
      title: texts.monthTitle,
      empty: texts.monthEmpty,
    });
  }

  private async reply(
    ctx: Context,
    employee: Employee,
    from: Date,
    to: Date,
    labels: SummaryTexts,
  ): Promise<void> {
    const summary = await this.workLogs.employeeSummary(employee.id, from, to);

    if (summary.totalQuantity === 0) {
      await ctx.reply(labels.empty, { reply_markup: mainMenu() });
      return;
    }

    const lines = [
      labels.title(summary.totalQuantity, money(summary.totalAmount)),
      '',
      ...summary.byProduct.map((b) => texts.byProductLine(b.name, b.quantity, money(b.amount))),
    ];

    await ctx.reply(lines.join('\n'), { reply_markup: mainMenu() });
  }
}
