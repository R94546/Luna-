import { HttpException } from '@nestjs/common';

/**
 * Ошибка бизнес-логики.
 *
 * `code` — машинный идентификатор для логики клиента (Flutter реагирует
 * на INSUFFICIENT_STOCK иначе, чем на VALIDATION_ERROR).
 * `messageKey` — ключ из словаря i18n; в текст его превращает
 * AllExceptionsFilter, когда уже знает язык из заголовка Accept-Language.
 * `details` — данные для подстановки в интерфейс.
 *
 * Готовый текст здесь не хранится намеренно: сервис не знает языка
 * пользователя, а исключение может подняться из фонового обработчика,
 * где HTTP-запроса нет вовсе.
 */
export class AppException extends HttpException {
  constructor(
    status: number,
    readonly code: string,
    readonly messageKey: string,
    readonly params?: Record<string, unknown>,
    readonly details?: Record<string, unknown>,
  ) {
    super({ code, messageKey, params, details }, status);
  }
}

/**
 * Частые ошибки — фабрики, чтобы коды и ключи не расползались
 * строковыми литералами по сервисам.
 */
export const Errors = {
  notFound: (entity: string) =>
    new AppException(404, 'NOT_FOUND', 'error.not_found', { entity }),

  duplicate: (field: string) =>
    new AppException(409, 'DUPLICATE', 'error.duplicate', { field }, { field }),

  forbiddenRole: () => new AppException(403, 'FORBIDDEN_ROLE', 'error.forbidden_role'),

  subscriptionExpired: () =>
    new AppException(403, 'SUBSCRIPTION_EXPIRED', 'error.subscription_expired'),

  invalidCredentials: () =>
    new AppException(401, 'INVALID_CREDENTIALS', 'error.invalid_credentials'),

  insufficientStock: (
    productId: string,
    productName: string,
    available: number,
    requested: number,
  ) =>
    new AppException(
      422,
      'INSUFFICIENT_STOCK',
      'error.insufficient_stock',
      { productName, available },
      { productId, productName, available, requested },
    ),

  invalidStatusTransition: (from: string, to: string) =>
    new AppException(422, 'INVALID_STATUS_TRANSITION', 'error.invalid_status_transition', { from, to }, { from, to }),

  periodAlreadyClosed: () =>
    new AppException(422, 'PERIOD_ALREADY_CLOSED', 'error.period_already_closed'),

  periodOverlap: (from: string, to: string) =>
    new AppException(422, 'PERIOD_OVERLAP', 'error.period_overlap', { from, to }, { from, to }),

  rateNotFound: (operation: string) =>
    new AppException(422, 'RATE_NOT_FOUND', 'error.rate_not_found', { operation }),

  telegramAlreadyLinked: () =>
    new AppException(409, 'TELEGRAM_ALREADY_LINKED', 'error.telegram_already_linked'),

  linkCodeInvalid: () => new AppException(400, 'LINK_CODE_INVALID', 'error.link_code_invalid'),

  workLogNotPending: () =>
    new AppException(422, 'WORK_LOG_NOT_PENDING', 'error.work_log_not_pending'),
};
