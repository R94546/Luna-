import { Injectable, Logger } from '@nestjs/common';
import { Bot, Context } from 'grammy';
import { PrismaService } from '../../../prisma/prisma.service';
import { texts } from '../bot-texts';
import { EmployeeGuard, mainMenu, showMenu } from '../telegram.utils';

/**
 * `/start` и привязка Telegram-аккаунта к сотруднику.
 *
 * Единственный обработчик, который работает и с непривязанным отправителем:
 * до успешной привязки сотрудника по telegram_user_id ещё не найти,
 * поэтому guard применяется только к ветке «код не передан».
 */
@Injectable()
export class StartHandler {
  private readonly logger = new Logger(StartHandler.name);

  constructor(private readonly prisma: PrismaService) {}

  register(bot: Bot, guard: EmployeeGuard): void {
    bot.command('start', (ctx) => this.onStart(ctx, guard));
    bot.command('help', (ctx) => ctx.reply(texts.help));
    bot.callbackQuery('menu', (ctx) => guard(ctx, (employee) => showMenu(ctx, employee)));
  }

  /** `/start` без кода — меню; с кодом — привязка аккаунта. */
  private async onStart(ctx: Context, guard: EmployeeGuard): Promise<void> {
    const code = ctx.match?.toString().trim().toUpperCase();
    const tgId = ctx.from?.id;
    if (!tgId) return;

    if (!code) {
      await guard(ctx, (employee) => showMenu(ctx, employee));
      return;
    }

    await this.linkAccount(ctx, tgId, code);
  }

  private async linkAccount(ctx: Context, tgId: number, code: string): Promise<void> {
    const existing = await this.prisma.employee.findFirst({
      where: { telegramUserId: BigInt(tgId) },
    });

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

    // Гашение кода и привязка — одной транзакцией: иначе при сбое между
    // ними код остался бы действующим уже после успешной привязки.
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
      reply_markup: mainMenu(),
    });
  }
}
