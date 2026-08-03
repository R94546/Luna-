import { Injectable } from '@nestjs/common';
import { OrderStatus, Prisma, WorkLogStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import {
  DashboardDto,
  ProductionDto,
  ProfitDto,
  TopProductsDto,
} from './dto/analytics.dto';
import {
  Period,
  changePercent,
  customPeriod,
  isoDate,
  previousPeriod,
  resolvePeriod,
} from './period';

const ZERO = new Prisma.Decimal(0);

/** Итоги периода — то, из чего складывается вся остальная арифметика. */
interface Totals {
  revenue: Prisma.Decimal;
  cogs: Prisma.Decimal;
  expenses: Prisma.Decimal;
  salaries: Prisma.Decimal;
  unitsProduced: number;
  unitsSold: number;
}

@Injectable()
export class AnalyticsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Главный экран одним запросом.
   *
   * Не пятью: сеть в цехе плохая, и пять параллельных запросов дают пять
   * шансов показать владельцу наполовину загруженный экран.
   */
  async dashboard(dto: DashboardDto) {
    const period = this.periodFrom(dto);
    const previous = previousPeriod(period);

    const [current, before, cashBalance, salaryDebt, alerts, chart, top] = await Promise.all([
      this.totals(period),
      this.totals(previous),
      this.cashBalance(),
      this.salaryDebt(),
      this.alerts(),
      this.revenueChart(period),
      this.topProducts({ ...dto, limit: 5, sort: 'revenue' }),
    ]);

    const now = this.derive(current);
    const then = this.derive(before);

    return {
      period: { from: isoDate(period.from), to: isoDate(period.to), label: period.label },
      revenue: metric(now.revenue, then.revenue),
      grossProfit: metric(now.grossProfit, then.grossProfit),
      netProfit: metric(now.netProfit, then.netProfit),
      expenses: metric(now.expenses, then.expenses),
      salaries: metric(now.salaries, then.salaries),
      cashBalance: cashBalance.toString(),
      salaryDebt: salaryDebt.toString(),
      unitsProduced: current.unitsProduced,
      unitsSold: current.unitsSold,
      alerts,
      revenueChart: chart,
      topProducts: top.items,
    };
  }

  /**
   * Прибыль с раскладкой.
   *
   * Отдаём все слагаемые, а не только итог: владелец, увидев падение,
   * первым делом спрашивает «из-за чего», и ответ должен быть на том же
   * экране, а не в другом отчёте.
   */
  async profit(dto: ProfitDto) {
    const period = this.periodFrom(dto);
    const previous = previousPeriod(period);

    const [current, before] = await Promise.all([this.totals(period), this.totals(previous)]);

    const now = this.derive(current);
    const then = this.derive(before);

    return {
      period: { from: isoDate(period.from), to: isoDate(period.to), label: period.label },
      revenue: metric(now.revenue, then.revenue),
      cogs: metric(now.cogs, then.cogs),
      grossProfit: metric(now.grossProfit, then.grossProfit),
      expenses: metric(now.expenses, then.expenses),
      salaries: metric(now.salaries, then.salaries),
      netProfit: metric(now.netProfit, then.netProfit),
      margin: now.revenue.eq(0)
        ? null
        : Math.round(now.netProfit.div(now.revenue).toNumber() * 1000) / 10,
    };
  }

  /**
   * Топ товаров.
   *
   * Считается по позициям продаж, а не по продажам: одна продажа содержит
   * несколько моделей, и приписать её выручку одной из них нельзя.
   */
  async topProducts(dto: TopProductsDto) {
    const period = this.periodFrom(dto);

    const grouped = await this.prisma.saleItem.groupBy({
      by: ['productId'],
      where: { sale: this.soldIn(period) },
      _sum: { quantity: true, total: true },
    });

    if (grouped.length === 0) {
      return { period: this.periodLabel(period), items: [] };
    }

    // Себестоимость проданного берётся из снимков позиций, а не из текущей
    // цены товара: иначе прошлые продажи начнут «дорожать» вслед за
    // пересчётом калькулятора.
    const costs = await this.prisma.saleItem.findMany({
      where: { sale: this.soldIn(period) },
      select: { productId: true, quantity: true, costPriceSnapshot: true },
    });

    const costByProduct = new Map<string, Prisma.Decimal>();
    for (const row of costs) {
      const previous = costByProduct.get(row.productId) ?? ZERO;
      costByProduct.set(row.productId, previous.plus(row.costPriceSnapshot.mul(row.quantity)));
    }

    const products = await this.prisma.product.findMany({
      where: { id: { in: grouped.map((g) => g.productId) } },
      select: { id: true, sku: true, name: true },
    });
    const byId = new Map(products.map((p) => [p.id, p]));

    const items = grouped
      .map((g) => {
        const revenue = g._sum.total ?? ZERO;
        const cost = costByProduct.get(g.productId) ?? ZERO;
        const product = byId.get(g.productId);

        return {
          id: g.productId,
          sku: product?.sku ?? '',
          name: product?.name ?? '',
          unitsSold: g._sum.quantity ?? 0,
          revenue: revenue.toString(),
          profit: revenue.minus(cost).toString(),
        };
      })
      .sort((a, b) => {
        if (dto.sort === 'units') return b.unitsSold - a.unitsSold;
        if (dto.sort === 'profit') return Number(b.profit) - Number(a.profit);
        return Number(b.revenue) - Number(a.revenue);
      })
      .slice(0, dto.limit);

    return { period: this.periodLabel(period), items };
  }

  /** Выпуск: по дням, по сотрудникам или по моделям — три взгляда на одно. */
  async production(dto: ProductionDto) {
    const period = this.periodFrom(dto);

    const where = {
      status: WorkLogStatus.APPROVED,
      workDate: { gte: period.from, lte: period.to },
    };

    if (dto.groupBy === 'day') {
      const logs = await this.prisma.workLog.groupBy({
        by: ['workDate'],
        where,
        _sum: { quantity: true, amount: true },
        orderBy: { workDate: 'asc' },
      });

      return {
        period: this.periodLabel(period),
        groupBy: dto.groupBy,
        items: logs.map((l) => ({
          key: isoDate(l.workDate),
          label: isoDate(l.workDate),
          quantity: l._sum.quantity ?? 0,
          amount: (l._sum.amount ?? ZERO).toString(),
        })),
      };
    }

    const field = dto.groupBy === 'employee' ? 'employeeId' : 'productId';

    const logs = await this.prisma.workLog.groupBy({
      by: [field],
      where,
      _sum: { quantity: true, amount: true },
    });

    const ids = logs.map((l) => l[field]);
    const names =
      dto.groupBy === 'employee'
        ? new Map(
            (
              await this.prisma.employee.findMany({
                where: { id: { in: ids } },
                select: { id: true, fullName: true },
              })
            ).map((e) => [e.id, e.fullName]),
          )
        : new Map(
            (
              await this.prisma.product.findMany({
                where: { id: { in: ids } },
                select: { id: true, name: true },
              })
            ).map((p) => [p.id, p.name]),
          );

    return {
      period: this.periodLabel(period),
      groupBy: dto.groupBy,
      items: logs
        .map((l) => ({
          key: l[field],
          label: names.get(l[field]) ?? '',
          quantity: l._sum.quantity ?? 0,
          amount: (l._sum.amount ?? ZERO).toString(),
        }))
        .sort((a, b) => b.quantity - a.quantity),
    };
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  /**
   * Слагаемые прибыли за период.
   *
   * Зарплата берётся по ВЫПЛАТАМ, а не по начислениям: владелец мыслит
   * кассовым методом — «сколько денег ушло в этом месяце». Начисленное,
   * но не выданное, показывается отдельной строкой «долг по зарплате»,
   * иначе оно дважды повлияло бы на одну и ту же цифру.
   */
  private async totals(period: Period): Promise<Totals> {
    const [sales, expenses, salaries, produced, sold] = await Promise.all([
      this.prisma.sale.aggregate({
        where: this.soldIn(period),
        _sum: { totalAmount: true, totalCost: true },
      }),
      this.prisma.expense.aggregate({
        where: { spentAt: { gte: period.from, lte: period.to } },
        _sum: { amount: true },
      }),
      this.prisma.salaryPayment.aggregate({
        where: { paidAt: { gte: period.from, lte: period.to } },
        _sum: { amount: true },
      }),
      this.prisma.workLog.aggregate({
        where: {
          status: WorkLogStatus.APPROVED,
          workDate: { gte: period.from, lte: period.to },
        },
        _sum: { quantity: true },
      }),
      this.prisma.saleItem.aggregate({
        where: { sale: this.soldIn(period) },
        _sum: { quantity: true },
      }),
    ]);

    return {
      revenue: sales._sum.totalAmount ?? ZERO,
      cogs: sales._sum.totalCost ?? ZERO,
      expenses: expenses._sum.amount ?? ZERO,
      salaries: salaries._sum.amount ?? ZERO,
      unitsProduced: produced._sum.quantity ?? 0,
      unitsSold: sold._sum.quantity ?? 0,
    };
  }

  private derive(t: Totals) {
    const grossProfit = t.revenue.minus(t.cogs);

    return {
      revenue: t.revenue,
      cogs: t.cogs,
      expenses: t.expenses,
      salaries: t.salaries,
      grossProfit,
      netProfit: grossProfit.minus(t.expenses).minus(t.salaries),
    };
  }

  /**
   * Сторнированные продажи не выручка.
   *
   * Условие живёт одним методом: пропусти его в любом из пяти мест, где
   * считаются деньги, — и отчёт разойдётся сам с собой.
   */
  private soldIn(period: Period): Prisma.SaleWhereInput {
    return { cancelledAt: null, soldAt: { gte: period.from, lte: period.to } };
  }

  private async cashBalance(): Promise<Prisma.Decimal> {
    const accounts = await this.prisma.cashAccount.aggregate({
      where: { isActive: true },
      _sum: { balance: true },
    });

    return accounts._sum.balance ?? ZERO;
  }

  /** Начислено, но не выдано — то, что цех должен рабочим прямо сейчас. */
  private async salaryDebt(): Promise<Prisma.Decimal> {
    const entries = await this.prisma.payrollEntry.aggregate({
      where: { isPaid: false },
      _sum: { toPay: true },
    });

    return entries._sum.toPay ?? ZERO;
  }

  /** Бейджи в навигации: красная точка на разделе, где что-то ждёт. */
  private async alerts() {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const [pendingWorkLogs, products, overdueOrders] = await Promise.all([
      this.prisma.workLog.count({ where: { status: WorkLogStatus.PENDING } }),
      this.prisma.product.findMany({
        where: { isActive: true, deletedAt: null },
        select: { stockQuantity: true, minStockLevel: true },
      }),
      this.prisma.order.count({
        where: {
          dueDate: { lt: today },
          status: { notIn: [OrderStatus.ISSUED, OrderStatus.CANCELLED] },
        },
      }),
    ]);

    return {
      pendingWorkLogs,
      // Сравнение двух колонок между собой Prisma не выражает в where —
      // фильтруем в памяти. Товаров в цехе десятки, не миллионы.
      lowStockProducts: products.filter((p) => p.stockQuantity <= p.minStockLevel).length,
      overdueOrders,
    };
  }

  /** Выручка и прибыль по дням — то, что рисуется графиком на главной. */
  private async revenueChart(period: Period) {
    const sales = await this.prisma.sale.findMany({
      where: this.soldIn(period),
      select: { soldAt: true, totalAmount: true, totalCost: true },
      orderBy: { soldAt: 'asc' },
    });

    const byDay = new Map<string, { revenue: Prisma.Decimal; profit: Prisma.Decimal }>();

    for (const sale of sales) {
      const day = isoDate(sale.soldAt);
      const acc = byDay.get(day) ?? { revenue: ZERO, profit: ZERO };

      byDay.set(day, {
        revenue: acc.revenue.plus(sale.totalAmount),
        profit: acc.profit.plus(sale.totalAmount.minus(sale.totalCost)),
      });
    }

    return [...byDay.entries()].map(([date, v]) => ({
      date,
      revenue: v.revenue.toString(),
      profit: v.profit.toString(),
    }));
  }

  private periodFrom(dto: { period: 'week' | 'month' | 'quarter' | 'year'; dateFrom?: string; dateTo?: string }): Period {
    return dto.dateFrom && dto.dateTo
      ? customPeriod(dto.dateFrom, dto.dateTo)
      : resolvePeriod(dto.period);
  }

  private periodLabel(period: Period) {
    return { from: isoDate(period.from), to: isoDate(period.to), label: period.label };
  }
}

/**
 * Показатель с динамикой.
 *
 * Абсолютная цифра без сравнения владельцу мало что говорит: 84 миллиона
 * выручки — это хорошо или плохо, видно только рядом с прошлым периодом.
 */
function metric(current: Prisma.Decimal, previous: Prisma.Decimal) {
  return {
    value: current.toString(),
    previous: previous.toString(),
    changePercent: changePercent(current.toString(), previous.toString()),
  };
}
