import { OrderStatus } from '@prisma/client';
import { availableTransitions, canTransition } from './order-status';

const ALL = Object.values(OrderStatus);

describe('автомат статусов заказа', () => {
  describe('разрешённые переходы', () => {
    it.each([
      [OrderStatus.NEW, OrderStatus.IN_PROGRESS],
      [OrderStatus.IN_PROGRESS, OrderStatus.READY],
      [OrderStatus.READY, OrderStatus.ISSUED],
    ])('%s → %s', (from, to) => {
      expect(canTransition(from, to)).toBe(true);
    });

    /** Отменить можно на любом шаге, пока заказ не закрыт. */
    it.each([OrderStatus.NEW, OrderStatus.IN_PROGRESS, OrderStatus.READY])(
      '%s → CANCELLED',
      (from) => {
        expect(canTransition(from, OrderStatus.CANCELLED)).toBe(true);
      },
    );
  });

  describe('запрещённые переходы', () => {
    /**
     * Назад ходить нельзя. Заказ, вернувшийся из READY в NEW, означал бы,
     * что произведённое куда-то делось.
     */
    it.each([
      [OrderStatus.IN_PROGRESS, OrderStatus.NEW],
      [OrderStatus.READY, OrderStatus.IN_PROGRESS],
      [OrderStatus.READY, OrderStatus.NEW],
      [OrderStatus.ISSUED, OrderStatus.READY],
    ])('%s → %s', (from, to) => {
      expect(canTransition(from, to)).toBe(false);
    });

    /** Через шаг тоже нельзя: заказ не может стать готовым, не начавшись. */
    it.each([
      [OrderStatus.NEW, OrderStatus.READY],
      [OrderStatus.NEW, OrderStatus.ISSUED],
      [OrderStatus.IN_PROGRESS, OrderStatus.ISSUED],
    ])('%s → %s (через шаг)', (from, to) => {
      expect(canTransition(from, to)).toBe(false);
    });

    it.each(ALL)('%s → сам в себя', (status) => {
      expect(canTransition(status, status)).toBe(false);
    });
  });

  describe('терминальные состояния', () => {
    /**
     * Выданный заказ закрыт: товар уехал к покупателю, и любой переход
     * из ISSUED означал бы, что он вернулся в цех сам собой.
     */
    it.each([OrderStatus.ISSUED, OrderStatus.CANCELLED])('из %s нет выходов', (status) => {
      expect(availableTransitions(status)).toEqual([]);
    });

    it.each(ALL)('отменённый заказ не оживает переходом в %s', (to) => {
      expect(canTransition(OrderStatus.CANCELLED, to)).toBe(false);
    });
  });

  describe('availableTransitions', () => {
    it('совпадает с canTransition для всех пар', () => {
      for (const from of ALL) {
        const allowed = availableTransitions(from);

        for (const to of ALL) {
          expect(canTransition(from, to)).toBe(allowed.includes(to));
        }
      }
    });

    it('знает каждый статус схемы', () => {
      // Новый статус в enum'е без ветки в автомате уронил бы переход
      // на undefined уже в проде.
      for (const status of ALL) {
        expect(Array.isArray(availableTransitions(status))).toBe(true);
      }
    });

    it('до выдачи всегда есть куда двинуться', () => {
      for (const status of [OrderStatus.NEW, OrderStatus.IN_PROGRESS, OrderStatus.READY]) {
        expect(availableTransitions(status).length).toBeGreaterThan(0);
      }
    });

    /** Граф не должен позволять вернуться в уже пройденный статус. */
    it('не содержит циклов', () => {
      const order = [
        OrderStatus.NEW,
        OrderStatus.IN_PROGRESS,
        OrderStatus.READY,
        OrderStatus.ISSUED,
      ];

      for (const [index, from] of order.entries()) {
        for (const to of availableTransitions(from)) {
          if (to === OrderStatus.CANCELLED) continue;
          expect(order.indexOf(to)).toBeGreaterThan(index);
        }
      }
    });
  });
});
