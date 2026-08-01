import { HttpException } from '@nestjs/common';

/**
 * Ошибка бизнес-логики с машинным кодом.
 *
 * `code` — для логики клиента (Flutter реагирует на INSUFFICIENT_STOCK иначе,
 * чем на VALIDATION_ERROR), `message` — готовый к показу текст,
 * `details` — данные для подстановки в интерфейс.
 *
 * Парсить `message` на клиенте нельзя — он меняется при переводе и правках
 * текстов. Именно поэтому код вынесен в отдельное поле.
 */
export class AppException extends HttpException {
  constructor(
    status: number,
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super({ code, message, details }, status);
  }
}

/** Частые ошибки — фабрики, чтобы коды не расползались строковыми литералами. */
export const Errors = {
  notFound: (entity: string) =>
    new AppException(404, 'NOT_FOUND', `${entity} не найден`),

  forbiddenRole: () =>
    new AppException(403, 'FORBIDDEN_ROLE', 'Недостаточно прав для этой операции'),

  subscriptionExpired: () =>
    new AppException(403, 'SUBSCRIPTION_EXPIRED', 'Срок подписки истёк'),

  insufficientStock: (productName: string, available: number, requested: number, productId: string) =>
    new AppException(
      422,
      'INSUFFICIENT_STOCK',
      `На складе только ${available} шт. модели «${productName}»`,
      { productId, productName, available, requested },
    ),

  invalidStatusTransition: (from: string, to: string) =>
    new AppException(
      422,
      'INVALID_STATUS_TRANSITION',
      `Нельзя перевести заказ из статуса «${from}» в «${to}»`,
      { from, to },
    ),

  periodAlreadyClosed: () =>
    new AppException(422, 'PERIOD_ALREADY_CLOSED', 'Зарплатный период уже закрыт'),

  invalidCredentials: () =>
    new AppException(401, 'INVALID_CREDENTIALS', 'Неверный телефон или пароль'),
};
