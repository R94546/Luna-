import { Prisma } from '@prisma/client';
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
export const TENANT_MODELS = new Set<string>([
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
  'IdempotencyKey',
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
 * Живёт отдельно от PrismaService намеренно: это самый критичный для
 * безопасности код в системе, а зависит он только от tenant-контекста.
 * Отдельной функцией его можно прогнать целиком, не поднимая PrismaClient
 * и не заводя базу.
 *
 * TODO при переходе на Prisma 6+: заменить $use на client extensions
 * ($extends с query.$allModels.$allOperations) — семантика та же.
 */
export function createTenantMiddleware(): Prisma.Middleware {
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
