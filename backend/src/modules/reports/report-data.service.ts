import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { ReportType } from './dto/report.dto';
import { ReportDocument, ReportTable, formatDate } from './report-document';

/** Русские подписи категорий кассы — те же, что в приложении. */
const CASH_CATEGORY: Record<string, string> = {
  SALE: 'Продажа',
  EXPENSE: 'Расход',
  SALARY: 'Зарплата',
  INVESTMENT: 'Внесение',
  WITHDRAWAL: 'Изъятие',
  TRANSFER: 'Перевод',
  OTHER: 'Прочее',
};

const MOVEMENT_TYPE: Record<string, string> = {
  PRODUCTION_IN: 'Выпуск',
  PURCHASE_IN: 'Закупка',
  RETURN_IN: 'Возврат',
  SALE_OUT: 'Продажа',
  ORDER_OUT: 'Выдача заказа',
  WRITE_OFF: 'Списание',
  ADJUSTMENT: 'Инвентаризация',
};

/**
 * Данные отчётов.
 *
 * Считает по тем же таблицам, что и экраны, но без пагинации: отчёт за год —
 * это все строки, а не первая сотня. Верхняя граница периода берётся концом
 * дня: `dateTo` в запросе — это включительно, и продажа в 18:00 последнего
 * дня обязана попасть в отчёт.
 */
@Injectable()
export class ReportDataService {
  constructor(private readonly prisma: PrismaService) {}

  async build(type: ReportType, dateFrom: string, dateTo: string): Promise<ReportDocument> {
    const from = new Date(`${dateFrom}T00:00:00.000Z`);
    const to = new Date(`${dateTo}T23:59:59.999Z`);
    const subtitle = `Период: ${formatDate(from)} — ${formatDate(to)}`;

    const tables = await this.tablesFor(type, from, to, dateFrom, dateTo);

    return { title: TITLES[type], subtitle, tables };
  }

  private tablesFor(
    type: ReportType,
    from: Date,
    to: Date,
    dateFrom: string,
    dateTo: string,
  ): Promise<ReportTable[]> {
    switch (type) {
      case 'FINANCE':
        return this.finance(from, to);
      case 'SALES':
        return this.sales(from, to);
      case 'PAYROLL':
        return this.payroll(dateFrom, dateTo);
      case 'PRODUCTION':
        return this.production(dateFrom, dateTo);
      case 'STOCK':
        return this.stock(from, to);
    }
  }

  // ── Финансы ──────────────────────────────────────────────────────────────

  private async finance(from: Date, to: Date): Promise<ReportTable[]> {
    const [transactions, byCategory, expenses] = await Promise.all([
      this.prisma.cashTransaction.findMany({
        where: { occurredAt: { gte: from, lte: to } },
        include: { account: { select: { name: true } } },
        orderBy: { occurredAt: 'asc' },
      }),
      this.prisma.cashTransaction.groupBy({
        by: ['direction', 'category'],
        where: { occurredAt: { gte: from, lte: to } },
        _sum: { amount: true },
      }),
      this.prisma.expense.findMany({
        where: { spentAt: { gte: from, lte: to } },
        include: { category: { select: { name: true } } },
        orderBy: { spentAt: 'asc' },
      }),
    ]);

    const income = sum(byCategory.filter((r) => r.direction === 'IN').map((r) => r._sum.amount));
    const outcome = sum(byCategory.filter((r) => r.direction === 'OUT').map((r) => r._sum.amount));

    return [
      {
        title: 'Итоги',
        columns: [
          { header: 'Показатель', width: 32 },
          { header: 'Сумма', width: 18, align: 'right', money: true },
        ],
        rows: [
          ['Приход', income.toNumber()],
          ['Расход', outcome.toNumber()],
          ['Итог за период', income.minus(outcome).toNumber()],
        ],
      },
      {
        title: 'По категориям',
        columns: [
          { header: 'Категория', width: 24 },
          { header: 'Направление', width: 14 },
          { header: 'Сумма', width: 18, align: 'right', money: true },
        ],
        rows: byCategory.map((row) => [
          CASH_CATEGORY[row.category] ?? row.category,
          row.direction === 'IN' ? 'Приход' : 'Расход',
          Number(row._sum.amount ?? 0),
        ]),
        emptyText: 'Движений денег за период не было',
      },
      {
        title: 'Расходы',
        columns: [
          { header: 'Дата', width: 12 },
          { header: 'Категория', width: 24 },
          { header: 'Комментарий', width: 32 },
          { header: 'Сумма', width: 18, align: 'right', money: true },
        ],
        rows: expenses.map((expense) => [
          formatDate(expense.spentAt),
          expense.category.name,
          expense.note ?? '',
          Number(expense.amount),
        ]),
        total: ['Итого', '', '', sum(expenses.map((e) => e.amount)).toNumber()],
        emptyText: 'Расходов за период не было',
      },
      {
        title: 'Журнал кассы',
        columns: [
          { header: 'Дата', width: 12 },
          { header: 'Касса', width: 20 },
          { header: 'Категория', width: 16 },
          { header: 'Приход', width: 16, align: 'right', money: true },
          { header: 'Расход', width: 16, align: 'right', money: true },
        ],
        rows: transactions.map((tx) => [
          formatDate(tx.occurredAt),
          tx.account.name,
          CASH_CATEGORY[tx.category] ?? tx.category,
          tx.direction === 'IN' ? Number(tx.amount) : null,
          tx.direction === 'OUT' ? Number(tx.amount) : null,
        ]),
        total: ['Итого', '', '', income.toNumber(), outcome.toNumber()],
        emptyText: 'Движений денег за период не было',
      },
    ];
  }

  // ── Продажи ──────────────────────────────────────────────────────────────

  private async sales(from: Date, to: Date): Promise<ReportTable[]> {
    const sales = await this.prisma.sale.findMany({
      where: { soldAt: { gte: from, lte: to } },
      include: {
        customer: { select: { name: true } },
        items: { include: { product: { select: { sku: true, name: true } } } },
      },
      orderBy: { soldAt: 'asc' },
    });

    // Сторнированные строки остаются в отчёте, но не входят в итоги:
    // выручкой они больше не считаются, а из истории их убирать нельзя.
    const active = sales.filter((sale) => sale.cancelledAt === null);
    const revenue = sum(active.map((s) => s.totalAmount));
    const cost = sum(active.map((s) => s.totalCost));

    return [
      {
        title: 'Продажи',
        columns: [
          { header: '№', width: 8, align: 'right' },
          { header: 'Дата', width: 12 },
          { header: 'Клиент', width: 22 },
          { header: 'Позиции', width: 34 },
          { header: 'Сумма', width: 16, align: 'right', money: true },
          { header: 'Себестоимость', width: 16, align: 'right', money: true },
          { header: 'Прибыль', width: 16, align: 'right', money: true },
        ],
        rows: sales.map((sale) => [
          sale.cancelledAt ? `${sale.saleNumber} (сторно)` : sale.saleNumber,
          formatDate(sale.soldAt),
          sale.customer?.name ?? '',
          sale.items.map((i) => `${i.product.name} ×${i.quantity}`).join(', '),
          Number(sale.totalAmount),
          Number(sale.totalCost),
          Number(new Prisma.Decimal(sale.totalAmount).minus(sale.totalCost)),
        ]),
        total: [
          'Итого',
          '',
          '',
          '',
          revenue.toNumber(),
          cost.toNumber(),
          revenue.minus(cost).toNumber(),
        ],
        emptyText: 'Продаж за период не было',
      },
      {
        title: 'По моделям',
        columns: [
          { header: 'Артикул', width: 14 },
          { header: 'Модель', width: 28 },
          { header: 'Продано, пар', width: 14, align: 'right' },
          { header: 'Выручка', width: 18, align: 'right', money: true },
        ],
        rows: byProduct(active),
        emptyText: 'Продаж за период не было',
      },
    ];
  }

  // ── Зарплата ─────────────────────────────────────────────────────────────

  private async payroll(dateFrom: string, dateTo: string): Promise<ReportTable[]> {
    const from = new Date(`${dateFrom}T00:00:00.000Z`);
    const to = new Date(`${dateTo}T00:00:00.000Z`);

    // Периоды, пересекающиеся с запрошенным диапазоном: зарплатный период
    // редко совпадает с календарным месяцем, и брать только полностью
    // вложенные значит потерять тот, что идёт сейчас.
    const [entries, payments] = await Promise.all([
      this.prisma.payrollEntry.findMany({
        where: { period: { periodStart: { lte: to }, periodEnd: { gte: from } } },
        include: {
          employee: { select: { fullName: true } },
          period: { select: { periodStart: true, periodEnd: true, status: true } },
        },
        orderBy: [{ period: { periodStart: 'asc' } }, { employee: { fullName: 'asc' } }],
      }),
      this.prisma.salaryPayment.findMany({
        where: { paidAt: { gte: from, lte: to } },
        include: { employee: { select: { fullName: true } } },
        orderBy: { paidAt: 'asc' },
      }),
    ]);

    return [
      {
        title: 'Начисления',
        columns: [
          { header: 'Сотрудник', width: 24 },
          { header: 'Период', width: 22 },
          { header: 'Выработка', width: 16, align: 'right', money: true },
          { header: 'Премия', width: 14, align: 'right', money: true },
          { header: 'Удержания', width: 14, align: 'right', money: true },
          { header: 'Аванс', width: 14, align: 'right', money: true },
          { header: 'К выплате', width: 16, align: 'right', money: true },
        ],
        rows: entries.map((entry) => [
          entry.employee.fullName,
          `${formatDate(entry.period.periodStart)} — ${formatDate(entry.period.periodEnd)}`,
          Number(entry.workAmount),
          Number(entry.bonus),
          Number(entry.deduction),
          Number(entry.advancePaid),
          Number(entry.toPay),
        ]),
        total: [
          'Итого',
          '',
          sum(entries.map((e) => e.workAmount)).toNumber(),
          sum(entries.map((e) => e.bonus)).toNumber(),
          sum(entries.map((e) => e.deduction)).toNumber(),
          sum(entries.map((e) => e.advancePaid)).toNumber(),
          sum(entries.map((e) => e.toPay)).toNumber(),
        ],
        emptyText: 'Начислений за период нет',
      },
      {
        title: 'Выплаты',
        columns: [
          { header: 'Дата', width: 12 },
          { header: 'Сотрудник', width: 24 },
          { header: 'Вид', width: 14 },
          { header: 'Комментарий', width: 28 },
          { header: 'Сумма', width: 16, align: 'right', money: true },
        ],
        rows: payments.map((payment) => [
          formatDate(payment.paidAt),
          payment.employee.fullName,
          PAYMENT_TYPE[payment.type] ?? payment.type,
          payment.note ?? '',
          Number(payment.amount),
        ]),
        total: ['Итого', '', '', '', sum(payments.map((p) => p.amount)).toNumber()],
        emptyText: 'Выплат за период не было',
      },
    ];
  }

  // ── Производство ─────────────────────────────────────────────────────────

  private async production(dateFrom: string, dateTo: string): Promise<ReportTable[]> {
    const from = new Date(`${dateFrom}T00:00:00.000Z`);
    const to = new Date(`${dateTo}T00:00:00.000Z`);

    // Только подтверждённая выработка: неподтверждённая — это заявка
    // рабочего, а не факт, и в отчёт о выпуске ей попадать рано.
    const logs = await this.prisma.workLog.findMany({
      where: { workDate: { gte: from, lte: to }, status: 'APPROVED' },
      include: {
        employee: { select: { fullName: true } },
        operation: { select: { name: true } },
        product: { select: { sku: true, name: true } },
      },
      orderBy: { workDate: 'asc' },
    });

    const byEmployee = new Map<string, { quantity: number; amount: Prisma.Decimal }>();
    const byOperation = new Map<string, { quantity: number; amount: Prisma.Decimal }>();

    for (const log of logs) {
      add(byEmployee, log.employee.fullName, log.quantity, log.amount);
      add(byOperation, log.operation.name, log.quantity, log.amount);
    }

    return [
      {
        title: 'По сотрудникам',
        columns: [
          { header: 'Сотрудник', width: 28 },
          { header: 'Сделано', width: 12, align: 'right' },
          { header: 'Заработано', width: 18, align: 'right', money: true },
        ],
        rows: [...byEmployee].map(([name, agg]) => [name, agg.quantity, agg.amount.toNumber()]),
        total: [
          'Итого',
          logs.reduce((acc, log) => acc + log.quantity, 0),
          sum(logs.map((l) => l.amount)).toNumber(),
        ],
        emptyText: 'Подтверждённой выработки за период нет',
      },
      {
        title: 'По операциям',
        columns: [
          { header: 'Операция', width: 28 },
          { header: 'Сделано', width: 12, align: 'right' },
          { header: 'Сумма', width: 18, align: 'right', money: true },
        ],
        rows: [...byOperation].map(([name, agg]) => [name, agg.quantity, agg.amount.toNumber()]),
        emptyText: 'Подтверждённой выработки за период нет',
      },
      {
        title: 'Выработка по дням',
        columns: [
          { header: 'Дата', width: 12 },
          { header: 'Сотрудник', width: 24 },
          { header: 'Операция', width: 20 },
          { header: 'Модель', width: 24 },
          { header: 'Кол-во', width: 10, align: 'right' },
          { header: 'Сумма', width: 16, align: 'right', money: true },
        ],
        rows: logs.map((log) => [
          formatDate(log.workDate),
          log.employee.fullName,
          log.operation.name,
          `${log.product.sku} · ${log.product.name}`,
          log.quantity,
          Number(log.amount),
        ]),
        emptyText: 'Подтверждённой выработки за период нет',
      },
    ];
  }

  // ── Склад ────────────────────────────────────────────────────────────────

  private async stock(from: Date, to: Date): Promise<ReportTable[]> {
    const [products, movements] = await Promise.all([
      this.prisma.product.findMany({
        where: { deletedAt: null },
        orderBy: { sku: 'asc' },
      }),
      this.prisma.stockMovement.findMany({
        where: { createdAt: { gte: from, lte: to } },
        include: { product: { select: { sku: true, name: true } } },
        orderBy: { createdAt: 'asc' },
      }),
    ]);

    const stockValue = products.reduce(
      (acc, product) => acc.plus(new Prisma.Decimal(product.costPrice).times(product.stockQuantity)),
      new Prisma.Decimal(0),
    );

    return [
      {
        title: 'Остатки',
        columns: [
          { header: 'Артикул', width: 14 },
          { header: 'Модель', width: 28 },
          { header: 'Остаток', width: 12, align: 'right' },
          { header: 'Минимум', width: 12, align: 'right' },
          { header: 'Себестоимость', width: 16, align: 'right', money: true },
          { header: 'Сумма запаса', width: 18, align: 'right', money: true },
        ],
        rows: products.map((product) => [
          product.sku,
          product.stockQuantity <= product.minStockLevel
            ? `${product.name} (заканчивается)`
            : product.name,
          product.stockQuantity,
          product.minStockLevel,
          Number(product.costPrice),
          Number(new Prisma.Decimal(product.costPrice).times(product.stockQuantity)),
        ]),
        total: ['Итого', '', '', '', '', stockValue.toNumber()],
        emptyText: 'Моделей в справочнике нет',
      },
      {
        title: 'Движения',
        columns: [
          { header: 'Дата', width: 12 },
          { header: 'Модель', width: 28 },
          { header: 'Тип', width: 18 },
          { header: 'Кол-во', width: 10, align: 'right' },
          { header: 'Остаток после', width: 14, align: 'right' },
          { header: 'Комментарий', width: 24 },
        ],
        rows: movements.map((movement) => [
          formatDate(movement.createdAt),
          `${movement.product.sku} · ${movement.product.name}`,
          MOVEMENT_TYPE[movement.type] ?? movement.type,
          movement.quantity,
          movement.balanceAfter,
          movement.note ?? '',
        ]),
        emptyText: 'Движений склада за период не было',
      },
    ];
  }
}

const TITLES: Record<ReportType, string> = {
  FINANCE: 'Финансовый отчёт',
  SALES: 'Отчёт по продажам',
  PAYROLL: 'Зарплатная ведомость',
  PRODUCTION: 'Отчёт по выпуску',
  STOCK: 'Складской отчёт',
};

const PAYMENT_TYPE: Record<string, string> = {
  ADVANCE: 'Аванс',
  SALARY: 'Зарплата',
  BONUS: 'Премия',
};

function sum(values: (Prisma.Decimal | null | undefined)[]): Prisma.Decimal {
  return values.reduce<Prisma.Decimal>(
    (acc, value) => acc.plus(value ?? 0),
    new Prisma.Decimal(0),
  );
}

function add(
  target: Map<string, { quantity: number; amount: Prisma.Decimal }>,
  key: string,
  quantity: number,
  amount: Prisma.Decimal,
): void {
  const current = target.get(key) ?? { quantity: 0, amount: new Prisma.Decimal(0) };

  target.set(key, {
    quantity: current.quantity + quantity,
    amount: current.amount.plus(amount),
  });
}

type SaleWithItems = Prisma.SaleGetPayload<{
  include: { items: { include: { product: { select: { sku: true; name: true } } } } };
}>;

function byProduct(sales: SaleWithItems[]): (string | number)[][] {
  const totals = new Map<string, { name: string; quantity: number; revenue: Prisma.Decimal }>();

  for (const sale of sales) {
    for (const item of sale.items) {
      const current = totals.get(item.product.sku) ?? {
        name: item.product.name,
        quantity: 0,
        revenue: new Prisma.Decimal(0),
      };

      totals.set(item.product.sku, {
        name: current.name,
        quantity: current.quantity + item.quantity,
        revenue: current.revenue.plus(item.total),
      });
    }
  }

  return [...totals]
    .sort((a, b) => b[1].revenue.comparedTo(a[1].revenue))
    .map(([sku, agg]) => [sku, agg.name, agg.quantity, agg.revenue.toNumber()]);
}
