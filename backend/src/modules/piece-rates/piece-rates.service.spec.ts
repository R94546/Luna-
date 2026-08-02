import { Prisma } from '@prisma/client';
import { AppException } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { PieceRatesService } from './piece-rates.service';

const OPERATION = '00000000-0000-0000-0000-0000000000aa';
const PRODUCT = '00000000-0000-0000-0000-0000000000bb';
const EMPLOYEE = '00000000-0000-0000-0000-0000000000cc';

/** Кандидат из таблицы расценок — минимум полей, которые читает резолвер. */
function rate(opts: {
  amount: number;
  productId?: string | null;
  employeeId?: string | null;
}) {
  return {
    id: `rate-${opts.amount}`,
    productId: opts.productId ?? null,
    employeeId: opts.employeeId ?? null,
    rate: new Prisma.Decimal(opts.amount),
  };
}

/**
 * Резолвер отбирает кандидатов одним запросом и ранжирует их в памяти,
 * поэтому для проверки правил достаточно подменить findMany — база
 * ничего не решает, решает сортировка по «заполненности» полей.
 */
function serviceWith(candidates: ReturnType<typeof rate>[], operationName = 'Tikish') {
  const findMany = jest.fn().mockResolvedValue(candidates);
  const findFirst = jest.fn().mockResolvedValue({ name: operationName });

  const prisma = {
    pieceRate: { findMany },
    operation: { findFirst },
  } as unknown as PrismaService;

  return { service: new PieceRatesService(prisma), findMany, findFirst };
}

describe('PieceRatesService.resolveRate', () => {
  describe('выбор от частного к общему', () => {
    it('берёт базовую ставку операции, когда других нет', async () => {
      const { service } = serviceWith([rate({ amount: 12000 })]);

      const result = await service.resolveRate({ operationId: OPERATION });

      expect(result.toString()).toBe('12000');
    });

    /** Ставка на модель специфичнее базовой — 16 000 против 12 000. */
    it('предпочитает ставку по модели базовой', async () => {
      const { service } = serviceWith([
        rate({ amount: 12000 }),
        rate({ amount: 16000, productId: PRODUCT }),
      ]);

      const result = await service.resolveRate({ operationId: OPERATION, productId: PRODUCT });

      expect(result.toString()).toBe('16000');
    });

    /** Персональная ставка мастера бьёт и модельную, и базовую. */
    it('предпочитает персональную ставку всем остальным', async () => {
      const { service } = serviceWith([
        rate({ amount: 12000 }),
        rate({ amount: 16000, productId: PRODUCT }),
        rate({ amount: 20000, productId: PRODUCT, employeeId: EMPLOYEE }),
      ]);

      const result = await service.resolveRate({
        operationId: OPERATION,
        productId: PRODUCT,
        employeeId: EMPLOYEE,
      });

      expect(result.toString()).toBe('20000');
    });

    /**
     * Персональная ставка без привязки к модели специфичнее модельной:
     * вес сотрудника (2) выше веса модели (1). Мастеру платят по его
     * ставке независимо от того, что он шьёт.
     */
    it('ставит сотрудника выше модели при конфликте', async () => {
      const { service } = serviceWith([
        rate({ amount: 16000, productId: PRODUCT }),
        rate({ amount: 18000, employeeId: EMPLOYEE }),
      ]);

      const result = await service.resolveRate({
        operationId: OPERATION,
        productId: PRODUCT,
        employeeId: EMPLOYEE,
      });

      expect(result.toString()).toBe('18000');
    });

    /** Порядок выдачи из БД не должен влиять на результат. */
    it('не зависит от порядка кандидатов', async () => {
      const candidates = [
        rate({ amount: 20000, productId: PRODUCT, employeeId: EMPLOYEE }),
        rate({ amount: 12000 }),
        rate({ amount: 16000, productId: PRODUCT }),
      ];

      const { service } = serviceWith([...candidates].reverse());

      const result = await service.resolveRate({
        operationId: OPERATION,
        productId: PRODUCT,
        employeeId: EMPLOYEE,
      });

      expect(result.toString()).toBe('20000');
    });
  });

  describe('когда ставки нет', () => {
    it('бросает RATE_NOT_FOUND с названием операции', async () => {
      const { service } = serviceWith([], 'Yelimlash');

      await expect(service.resolveRate({ operationId: OPERATION })).rejects.toMatchObject({
        code: 'RATE_NOT_FOUND',
        params: { operation: 'Yelimlash' },
      });
    });

    it('не падает, если операция тоже не найдена', async () => {
      const findMany = jest.fn().mockResolvedValue([]);
      const findFirst = jest.fn().mockResolvedValue(null);
      const prisma = {
        pieceRate: { findMany },
        operation: { findFirst },
      } as unknown as PrismaService;

      const error = await new PieceRatesService(prisma)
        .resolveRate({ operationId: OPERATION })
        .catch((e: unknown) => e);

      expect(error).toBeInstanceOf(AppException);
      expect((error as AppException).params).toEqual({ operation: '' });
    });
  });

  describe('условия отбора кандидатов', () => {
    /**
     * Три условия «или конкретное значение, или NULL» обязаны быть
     * отдельными элементами AND. Если сложить их в один объект, второй
     * ключ OR перезапишет первый ещё до Prisma — и ставка по модели
     * начнёт подбираться для чужого сотрудника.
     */
    it('разносит OR по отдельным элементам AND', async () => {
      const { service, findMany } = serviceWith([rate({ amount: 12000 })]);

      await service.resolveRate({
        operationId: OPERATION,
        productId: PRODUCT,
        employeeId: EMPLOYEE,
      });

      const { where } = findMany.mock.calls[0][0];

      expect(where.operationId).toBe(OPERATION);
      expect(where.AND).toHaveLength(3);
      expect(where.AND[0]).toEqual({ OR: [{ productId: PRODUCT }, { productId: null }] });
      expect(where.AND[1]).toEqual({ OR: [{ employeeId: EMPLOYEE }, { employeeId: null }] });
    });

    it('ищет только общие ставки, когда модель и сотрудник не заданы', async () => {
      const { service, findMany } = serviceWith([rate({ amount: 12000 })]);

      await service.resolveRate({ operationId: OPERATION });

      const { where } = findMany.mock.calls[0][0];

      expect(where.AND[0]).toEqual({ OR: [{ productId: null }, { productId: null }] });
      expect(where.AND[1]).toEqual({ OR: [{ employeeId: null }, { employeeId: null }] });
    });

    /**
     * Расценка, начавшая действовать позже запрошенной даты, не должна
     * попадать в выборку: пересчёт зарплаты за прошлый месяц обязан
     * давать тот же результат, что и в момент начисления.
     */
    it('отбирает ставки, действующие на указанную дату', async () => {
      const { service, findMany } = serviceWith([rate({ amount: 12000 })]);

      await service.resolveRate({ operationId: OPERATION, date: '2026-03-15' });

      const { where } = findMany.mock.calls[0][0];

      expect(where.validFrom).toEqual({ lte: new Date('2026-03-15') });
      expect(where.AND[2]).toEqual({
        OR: [{ validTo: null }, { validTo: { gte: new Date('2026-03-15') } }],
      });
    });

    it('без даты берёт текущий момент', async () => {
      const { service, findMany } = serviceWith([rate({ amount: 12000 })]);

      const before = Date.now();
      await service.resolveRate({ operationId: OPERATION });
      const after = Date.now();

      const { where } = findMany.mock.calls[0][0];
      const onDate: Date = where.validFrom.lte;

      expect(onDate.getTime()).toBeGreaterThanOrEqual(before);
      expect(onDate.getTime()).toBeLessThanOrEqual(after);
    });
  });

  /**
   * Ставка возвращается как Decimal, а не number: суммы в сумах доходят
   * до миллионов, и перевод во float на пути к work_logs.amount сломал бы
   * инвариант amount = quantity × rate, который стоит CHECK-констрейнтом.
   */
  it('возвращает Decimal, а не число', async () => {
    const { service } = serviceWith([rate({ amount: 12000 })]);

    const result = await service.resolveRate({ operationId: OPERATION });

    expect(result).toBeInstanceOf(Prisma.Decimal);
  });
});
