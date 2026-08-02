import { Employee } from '@prisma/client';
import { Context, InlineKeyboard } from 'grammy';
import { texts } from './bot-texts';

/**
 * Авторизация рабочего + вход в tenant-контекст.
 *
 * Реализацию держит TelegramService, обработчики получают её параметром:
 * так они не зависят ни от Prisma-поиска сотрудника, ни от AsyncLocalStorage,
 * и их можно тестировать, подставив тривиальную заглушку.
 */
export type EmployeeGuard = (
  ctx: Context,
  fn: (employee: Employee) => Promise<void>,
) => Promise<void>;

/** Главное меню. Одно на всех обработчиков, чтобы кнопки не разъехались. */
export function mainMenu(): InlineKeyboard {
  return new InlineKeyboard()
    .text(texts.btnReport, 'report')
    .row()
    .text(texts.btnToday, 'today')
    .text(texts.btnMonth, 'month');
}

export async function showMenu(ctx: Context, employee: Employee): Promise<void> {
  await ctx.reply(texts.menu(employee.fullName), { reply_markup: mainMenu() });
}

/**
 * Расценка на операцию не задана.
 *
 * Сверяем по коду AppException, а не по типу: work-logs бросает ошибку
 * прикладного слоя, и обработчику важен только повод показать рабочему
 * понятный текст вместо «ошибка сервера».
 */
export function isRateNotFoundError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { code: unknown }).code === 'RATE_NOT_FOUND'
  );
}
