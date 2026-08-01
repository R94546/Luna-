import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import { getTenant } from './tenant-context';

/**
 * Модели, у которых есть company_id и которые обязаны фильтроваться
 * по арендатору автоматически.
 *
 * Дочерние сущности (OrderItem, SaleItem, CostCalculationItem) в список
 * НЕ входят: у них нет company_id, изоляция обеспечивается через родителя.
 * Модели платформы (Company, User, RefreshToken, TelegramUpdate) — тоже нет,
 * ими управляет auth-слой явно.
 */
const TENANT_MODELS = new Set<string>([
  'Employee',
  'TelegramLinkCode',
  'Operation',
  'PieceRate',
  'Product',
  'StockMovement',
  'WorkLog',
  'PayrollPeriod',
  'PayrollEntry',
  'SalaryPayment',
  'Customer',
  'Order',
  'Sale',
  'CashAccount',
  'CashTransaction',
  'ExpenseCategory',
  'Expense',
  'Material',
  'CostCalculation',
  'Notification',
  'AuditLog',
]);

/** Операции, у которых company_id нужно дописать в data, а не в where. */
const CREATE_OPS = new Set(['create', 'createMany']);

/** Операции, у которых фильтруем where. */
const FILTERED_OPS = new Set([
  'findUnique',
  'findUniqueOrThrow',
  'findFirst',
  'findFirstOrThrow',
  'findMany',
  'update',
  'updateMany',
  'delete',
  'deleteMany',
  'count',
  'aggregate',
  'groupBy',
]);

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    super({
      log: [
        { emit: 'event', level: 'query' },
        { emit: 'stdout', level: 'warn' },
        { emit: 'stdout', level: 'error' },
      ],
    });

    this.$use(this.tenantMiddleware());
  }

  async onModuleInit(): Promise<void> {
    await this.$connect();

    if (process.env.NODE_ENV === 'development') {
      // @ts-expect-error — типы событий Prisma не выводятся из динамического log-конфига
      this.$on('query', (e: Prisma.QueryEvent) => {
        if (e.duration > 100) {
          this.logger.warn(`Медленный запрос (${e.duration} мс): ${e.query}`);
        }
      });
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }

  /**
   * Автоматическая изоляция арендаторов.
   *
   * Разработчик пишет `prisma.product.findMany()` — middleware превращает это
   * в `findMany({ where: { companyId } })`. Забыть фильтр физически нельзя,
   * а это самая опасная ошибка в мультиарендной системе: утечка данных
   * одного цеха другому.
   *
   * Опирается на extendedWhereUnique (GA с Prisma 5): в `where` у findUnique,
   * update и delete разрешены неуникальные поля рядом с уникальным.
   * Поэтому `findUnique({ where: { id } })` безопасно превращается в
   * `{ where: { id, companyId } }` — чужая запись отдаст null, а не данные.
   *
   * TODO при переходе на Prisma 6+: заменить $use на client extensions
   * ($extends с query.$allModels.$allOperations) — семантика та же.
   */
  private tenantMiddleware(): Prisma.Middleware {
    return async (params, next) => {
      const ctx = getTenant();

      if (!ctx?.companyId || !params.model || !TENANT_MODELS.has(params.model)) {
        return next(params);
      }

      const { companyId } = ctx;

      if (CREATE_OPS.has(params.action)) {
        params.args ??= {};

        // companyId из контекста ставится ПОСЛЕ данных вызывающего кода:
        // даже если сервис передаст чужой идентификатор, записан будет свой.
        if (params.action === 'createMany') {
          const rows = params.args.data;
          params.args.data = Array.isArray(rows)
            ? rows.map((row: Record<string, unknown>) => ({ ...row, companyId }))
            : { ...rows, companyId };
        } else {
          params.args.data = { ...params.args.data, companyId };
        }

        return next(params);
      }

      if (params.action === 'upsert') {
        params.args ??= {};
        params.args.where = { ...params.args.where, companyId };
        params.args.create = { ...params.args.create, companyId };
        return next(params);
      }

      if (FILTERED_OPS.has(params.action)) {
        params.args ??= {};
        params.args.where = { ...params.args.where, companyId };
        return next(params);
      }

      return next(params);
    };
  }

  /**
   * Инкремент пер-компанийного счётчика документов (заказ №14, продажа №203).
   *
   * INSERT ... ON CONFLICT DO UPDATE RETURNING — атомарно, одним запросом.
   * Строка счётчика блокируется до конца транзакции, поэтому два одновременных
   * заказа получат разные номера, а не одинаковые.
   *
   * Вызывать ТОЛЬКО внутри $transaction, передавая tx.
   */
  async nextNumber(
    tx: Prisma.TransactionClient,
    companyId: string,
    entity: 'order' | 'sale',
  ): Promise<number> {
    const rows = await tx.$queryRaw<{ last_value: number }[]>`
      INSERT INTO company_counters (company_id, entity, last_value)
      VALUES (${companyId}::uuid, ${entity}, 1)
      ON CONFLICT (company_id, entity)
      DO UPDATE SET last_value = company_counters.last_value + 1
      RETURNING last_value
    `;
    return rows[0].last_value;
  }
}
