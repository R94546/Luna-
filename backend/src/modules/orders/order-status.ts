import { OrderStatus } from '@prisma/client';

/**
 * Автомат статусов заказа.
 *
 * ```
 * NEW ──► IN_PROGRESS ──► READY ──► ISSUED
 *  │           │            │
 *  └───────────┴────────────┴──────► CANCELLED
 * ```
 *
 * Назад ходить нельзя. Заказ, вернувшийся из READY в NEW, означал бы, что
 * произведённое куда-то делось; из ISSUED — что товар, уже уехавший
 * к покупателю, снова в цехе.
 *
 * Отдельным модулем, а не методом сервиса: переходы нужны и при смене
 * статуса, и при отдаче карточки (`availableTransitions`), и в тестах.
 * Правило перехода должно быть записано ровно один раз.
 */
const TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  NEW: [OrderStatus.IN_PROGRESS, OrderStatus.CANCELLED],
  IN_PROGRESS: [OrderStatus.READY, OrderStatus.CANCELLED],
  READY: [OrderStatus.ISSUED, OrderStatus.CANCELLED],
  // Терминальные: выданный заказ закрыт, отменённый тоже.
  ISSUED: [],
  CANCELLED: [],
};

export function availableTransitions(from: OrderStatus): OrderStatus[] {
  return TRANSITIONS[from];
}

export function canTransition(from: OrderStatus, to: OrderStatus): boolean {
  return TRANSITIONS[from].includes(to);
}
