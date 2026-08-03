import { PrismaService } from '../../prisma/prisma.service';
import { IdempotencyService } from './idempotency.service';

const service = new IdempotencyService({} as PrismaService);

/**
 * Хеш тела — то, чем «повтор» отличается от «другой операции с тем же
 * ключом». Если он поедет от порядка полей, добросовестный повтор начнёт
 * получать 409 вместо результата, и пользователь заведёт вторую продажу
 * руками — ровно то, от чего защищались.
 */
describe('IdempotencyService.hashBody', () => {
  it('одинаковое тело даёт одинаковый хеш', () => {
    const body = { amount: '150000', employeeId: 'e-1' };

    expect(service.hashBody(body)).toBe(service.hashBody({ ...body }));
  });

  it('не зависит от порядка полей', () => {
    expect(service.hashBody({ a: 1, b: 2 })).toBe(service.hashBody({ b: 2, a: 1 }));
  });

  it('не зависит от порядка полей во вложенных объектах', () => {
    expect(service.hashBody({ outer: { a: 1, b: 2 } })).toBe(
      service.hashBody({ outer: { b: 2, a: 1 } }),
    );
  });

  /** Порядок в массиве — часть данных: [1,2] и [2,1] разные списки позиций. */
  it('зависит от порядка элементов массива', () => {
    expect(service.hashBody({ items: [1, 2] })).not.toBe(service.hashBody({ items: [2, 1] }));
  });

  it('различает разные суммы', () => {
    expect(service.hashBody({ amount: '150000' })).not.toBe(
      service.hashBody({ amount: '150001' }),
    );
  });

  /**
   * Строка и число — разные тела. «5000» и 5000 приходят из разных версий
   * клиента, и считать их одним запросом нельзя: денежные схемы принимают
   * оба вида, но записывают по-разному.
   */
  it('различает строку и число', () => {
    expect(service.hashBody({ amount: '5000' })).not.toBe(service.hashBody({ amount: 5000 }));
  });

  it('различает отсутствующее поле и null', () => {
    expect(service.hashBody({ note: null })).not.toBe(service.hashBody({}));
  });

  /** undefined в JSON не сериализуется — тело без поля и с undefined равны. */
  it('игнорирует undefined', () => {
    expect(service.hashBody({ a: 1, note: undefined })).toBe(service.hashBody({ a: 1 }));
  });

  it('различает вложенность', () => {
    expect(service.hashBody({ a: { b: 1 } })).not.toBe(service.hashBody({ 'a.b': 1 }));
  });

  it('переваривает пустое тело', () => {
    expect(service.hashBody({})).toHaveLength(64);
    expect(service.hashBody(undefined)).toHaveLength(64);
  });

  it('выдаёт sha256 в hex', () => {
    expect(service.hashBody({ a: 1 })).toMatch(/^[0-9a-f]{64}$/);
  });
});
