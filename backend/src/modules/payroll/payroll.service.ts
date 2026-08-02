import { Injectable } from '@nestjs/common';
import { PayrollPeriodStatus, Prisma, SalaryPaymentType, WorkLogStatus } from '@prisma/client';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreatePeriodDto, ListPeriodsDto, PreviewDto, UpdateEntryDto } from './dto/payroll.dto';

const ZERO = new Prisma.Decimal(0);

/** Начисление до записи в БД — то, что считается из выработки и правок мастера. */
export interface EntryAmounts {
  workAmount: Prisma.Decimal;
  bonus: Prisma.Decimal;
  deduction: Prisma.Decimal;
  advancePaid: Prisma.Decimal;
}

/**
 * Производные суммы начисления.
 *
 * Хранятся в таблице денормализованно (`total_accrued`, `to_pay`), потому
 * что ведомость и сводка по цеху читают их пачками и пересчитывать их
 * в каждом запросе незачем. Единственное место, где они вычисляются, —
 * здесь: иначе две формулы разойдутся, и разойдутся молча.
 */
export function derive(a: EntryAmounts) {
  const totalAccrued = a.workAmount.plus(a.bonus).minus(a.deduction);
  return { totalAccrued, toPay: totalAccrued.minus(a.advancePaid) };
}

@Injectable()
export class PayrollService {
  constructor(private readonly prisma: PrismaService) {}

  // ── Периоды ──────────────────────────────────────────────────────────────

  async findAllPeriods(dto: ListPeriodsDto) {
    const periods = await this.prisma.payrollPeriod.findMany({
      where: dto.status ? { status: dto.status } : {},
      orderBy: { periodStart: 'desc' },
      include: { _count: { select: { entries: true } } },
    });

    return periods.map((p) => ({
      id: p.id,
      periodStart: toIsoDate(p.periodStart),
      periodEnd: toIsoDate(p.periodEnd),
      status: p.status,
      totalAmount: p.totalAmount.toString(),
      employeeCount: p._count.entries,
      closedAt: p.closedAt,
    }));
  }

  async findOnePeriod(id: string) {
    const period = await this.loadPeriod(id);
    return this.presentPeriod(period.id);
  }

  /**
   * Открытие периода.
   *
   * Пересечение с существующим периодом запрещено. Формально двойного
   * начисления не случилось бы — выработку захватывает тот, кто закрылся
   * первым, — но до закрытия оба периода показывали бы одни и те же деньги,
   * и владелец увидел бы зарплатный фонд вдвое больше настоящего.
   */
  async createPeriod(dto: CreatePeriodDto) {
    const periodStart = new Date(dto.periodStart);
    const periodEnd = new Date(dto.periodEnd);

    const overlapping = await this.prisma.payrollPeriod.findFirst({
      where: { periodStart: { lte: periodEnd }, periodEnd: { gte: periodStart } },
    });

    if (overlapping) {
      throw Errors.periodOverlap(
        toIsoDate(overlapping.periodStart),
        toIsoDate(overlapping.periodEnd),
      );
    }

    const created = await this.prisma.payrollPeriod.create({
      data: { companyId: requireTenant().companyId, periodStart, periodEnd },
    });

    // Свежий период сразу считаем: открывать его и видеть нули — лишний шаг.
    return this.calculate(created.id);
  }

  /**
   * Пересчёт начислений.
   *
   * Идемпотентен по построению: суммы не накапливаются, а каждый раз
   * выводятся заново из выработки и выплат. Поэтому вызывать можно сколько
   * угодно — мастер добавил забытый отчёт, нажал «пересчитать», и ведомость
   * сошлась.
   *
   * Премии и удержания при этом сохраняются: их ставит человек, из
   * выработки их не вывести.
   */
  async calculate(periodId: string) {
    const period = await this.loadPeriod(periodId);
    this.assertOpen(period.status);

    await this.prisma.$transaction((tx) => this.recalculate(tx, period));

    return this.presentPeriod(periodId);
  }

  /**
   * Закрытие периода.
   *
   * Здесь и происходит защита от двойной оплаты: выработке проставляется
   * ссылка на начисление, и в следующий период те же строки уже не попадут —
   * `calculate` берёт только записи с `payrollEntryId IS NULL`.
   *
   * Пересчёт идёт внутри той же транзакции, что и захват: между «посчитали»
   * и «закрыли» мастер мог подтвердить ещё один отчёт, и без пересчёта
   * он был бы захвачен периодом, но не попал бы в сумму к выплате.
   */
  async close(periodId: string) {
    const period = await this.loadPeriod(periodId);
    this.assertOpen(period.status);

    await this.prisma.$transaction(async (tx) => {
      const entries = await this.recalculate(tx, period);

      for (const entry of entries) {
        // updateMany с payrollEntryId: null в условии — атомарный захват.
        // Строка, уже забранная параллельным закрытием, просто не обновится.
        await tx.workLog.updateMany({
          where: {
            employeeId: entry.employeeId,
            workDate: { gte: period.periodStart, lte: period.periodEnd },
            status: WorkLogStatus.APPROVED,
            payrollEntryId: null,
          },
          data: { payrollEntryId: entry.id },
        });
      }

      await tx.payrollPeriod.update({
        where: { id: periodId },
        data: { status: PayrollPeriodStatus.CLOSED, closedAt: new Date() },
      });
    });

    return this.presentPeriod(periodId);
  }

  // ── Начисления ───────────────────────────────────────────────────────────

  /** Премия и удержание — единственное, что в начислении правится руками. */
  async updateEntry(entryId: string, dto: UpdateEntryDto) {
    const entry = await this.prisma.payrollEntry.findFirst({
      where: { id: entryId },
      include: { period: true },
    });

    if (!entry) throw Errors.notFound('Hisoblash');
    this.assertOpen(entry.period.status);

    const amounts: EntryAmounts = {
      workAmount: entry.workAmount,
      bonus: dto.bonus !== undefined ? new Prisma.Decimal(dto.bonus) : entry.bonus,
      deduction: dto.deduction !== undefined ? new Prisma.Decimal(dto.deduction) : entry.deduction,
      advancePaid: entry.advancePaid,
    };

    await this.prisma.$transaction(async (tx) => {
      await tx.payrollEntry.update({
        where: { id: entryId },
        data: { ...amounts, ...derive(amounts) },
      });

      await this.refreshPeriodTotal(tx, entry.periodId);
    });

    return this.presentPeriod(entry.periodId);
  }

  /**
   * Что начислится, если закрыть период прямо сейчас.
   *
   * Ничего не создаёт и не меняет: владелец смотрит на цифру до того, как
   * заводить период. Считается по той же выборке, что и `calculate`.
   */
  async preview(dto: PreviewDto) {
    const from = new Date(dto.dateFrom);
    const to = new Date(dto.dateTo);

    const grouped = await this.sumUnclaimedWork(this.prisma, from, to);
    const employees = await this.namesFor([...grouped.keys()]);

    const rows = [...grouped.entries()]
      .map(([employeeId, workAmount]) => ({
        employee: { id: employeeId, fullName: employees.get(employeeId) ?? '' },
        workAmount: workAmount.toString(),
      }))
      .sort((a, b) => Number(b.workAmount) - Number(a.workAmount));

    const total = [...grouped.values()].reduce((sum, v) => sum.plus(v), ZERO);

    return {
      dateFrom: dto.dateFrom,
      dateTo: dto.dateTo,
      totalAmount: total.toString(),
      employeeCount: rows.length,
      entries: rows,
    };
  }

  /**
   * Пересчёт начисления после того, как сотруднику заплатили.
   *
   * Вызывается из выплаты внутри её же транзакции: `advance_paid` и `to_pay`
   * обязаны сойтись с кассой сразу, а не после того, как кто-нибудь нажмёт
   * «пересчитать». Считает из выплат заново — по той же формуле, что
   * и `calculate`, чтобы два пути не разошлись.
   */
  async refreshEntryAfterPayment(tx: Prisma.TransactionClient, entryId: string): Promise<void> {
    const entry = await tx.payrollEntry.findFirst({
      where: { id: entryId },
      include: { period: true },
    });

    if (!entry) return;

    const advances = await this.sumAdvances(
      tx,
      [entry.employeeId],
      entry.period.periodStart,
      entry.period.periodEnd,
    );

    const amounts: EntryAmounts = {
      workAmount: entry.workAmount,
      bonus: entry.bonus,
      deduction: entry.deduction,
      advancePaid: advances.get(entry.employeeId) ?? ZERO,
    };

    await tx.payrollEntry.update({
      where: { id: entryId },
      data: { ...amounts, ...derive(amounts) },
    });

    await this.refreshPeriodTotal(tx, entry.periodId);
  }

  /**
   * Начисление, к которому относится выплата.
   *
   * Явная ссылка от клиента приоритетнее: бухгалтер может гасить прошлый
   * период. Без неё ищем открытый период, накрывающий дату выплаты —
   * обычный случай аванса в середине месяца.
   */
  async findEntryForPayment(
    tx: Prisma.TransactionClient,
    employeeId: string,
    paidAt: Date,
    explicitEntryId?: string,
  ): Promise<string | null> {
    if (explicitEntryId) {
      const entry = await tx.payrollEntry.findFirst({
        where: { id: explicitEntryId, employeeId },
      });
      if (!entry) throw Errors.notFound('Hisoblash');
      return entry.id;
    }

    const entry = await tx.payrollEntry.findFirst({
      where: {
        employeeId,
        period: {
          status: PayrollPeriodStatus.OPEN,
          periodStart: { lte: paidAt },
          periodEnd: { gte: paidAt },
        },
      },
    });

    return entry?.id ?? null;
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  /**
   * Пересчёт всех начислений периода.
   *
   * Возвращает начисления, чтобы `close` мог сразу захватить по ним
   * выработку, не читая их повторно.
   */
  private async recalculate(
    tx: Prisma.TransactionClient,
    period: { id: string; periodStart: Date; periodEnd: Date },
  ) {
    const [work, existing] = await Promise.all([
      this.sumUnclaimedWork(tx, period.periodStart, period.periodEnd),
      tx.payrollEntry.findMany({ where: { periodId: period.id } }),
    ]);

    // Сотрудник, у которого уже есть начисление, но выработка исчезла
    // (отчёт отклонили после расчёта), обязан попасть в пересчёт с нулём —
    // иначе в ведомости останется сумма, которой ничего не соответствует.
    const employeeIds = new Set([...work.keys(), ...existing.map((e) => e.employeeId)]);
    if (employeeIds.size === 0) {
      await this.refreshPeriodTotal(tx, period.id);
      return [];
    }

    const advances = await this.sumAdvances(tx, [...employeeIds], period.periodStart, period.periodEnd);
    const byEmployee = new Map(existing.map((e) => [e.employeeId, e]));
    const companyId = requireTenant().companyId;

    const saved = [];

    for (const employeeId of employeeIds) {
      const previous = byEmployee.get(employeeId);

      const amounts: EntryAmounts = {
        workAmount: work.get(employeeId) ?? ZERO,
        bonus: previous?.bonus ?? ZERO,
        deduction: previous?.deduction ?? ZERO,
        advancePaid: advances.get(employeeId) ?? ZERO,
      };

      const data = { ...amounts, ...derive(amounts) };

      saved.push(
        previous
          ? await tx.payrollEntry.update({ where: { id: previous.id }, data })
          : await tx.payrollEntry.create({
              data: { companyId, periodId: period.id, employeeId, ...data },
            }),
      );
    }

    await this.refreshPeriodTotal(tx, period.id);

    return saved;
  }

  /**
   * Выработка, ещё не попавшая ни в одно начисление.
   *
   * `payrollEntryId: null` — тот самый фильтр, из-за которого закрытый
   * период невозможно оплатить дважды.
   */
  private async sumUnclaimedWork(
    client: Pick<PrismaService, 'workLog'> | Prisma.TransactionClient,
    from: Date,
    to: Date,
  ): Promise<Map<string, Prisma.Decimal>> {
    const grouped = await client.workLog.groupBy({
      by: ['employeeId'],
      where: {
        status: WorkLogStatus.APPROVED,
        workDate: { gte: from, lte: to },
        payrollEntryId: null,
      },
      _sum: { amount: true },
    });

    return new Map(grouped.map((g) => [g.employeeId, g._sum.amount ?? ZERO]));
  }

  /**
   * Авансы за период.
   *
   * Считаются из выплат, а не накапливаются инкрементом: выплату могут
   * завести задним числом, и единственный способ не разойтись — каждый раз
   * выводить сумму заново из первоисточника.
   */
  private async sumAdvances(
    tx: Prisma.TransactionClient,
    employeeIds: string[],
    from: Date,
    to: Date,
  ): Promise<Map<string, Prisma.Decimal>> {
    const grouped = await tx.salaryPayment.groupBy({
      by: ['employeeId'],
      where: {
        employeeId: { in: employeeIds },
        type: SalaryPaymentType.ADVANCE,
        paidAt: { gte: from, lte: to },
      },
      _sum: { amount: true },
    });

    return new Map(grouped.map((g) => [g.employeeId, g._sum.amount ?? ZERO]));
  }

  private async refreshPeriodTotal(tx: Prisma.TransactionClient, periodId: string) {
    const agg = await tx.payrollEntry.aggregate({
      where: { periodId },
      _sum: { totalAccrued: true },
    });

    await tx.payrollPeriod.update({
      where: { id: periodId },
      data: { totalAmount: agg._sum.totalAccrued ?? ZERO },
    });
  }

  private async loadPeriod(id: string) {
    const period = await this.prisma.payrollPeriod.findFirst({ where: { id } });
    if (!period) throw Errors.notFound('Oylik davri');
    return period;
  }

  private assertOpen(status: PayrollPeriodStatus) {
    if (status !== PayrollPeriodStatus.OPEN) throw Errors.periodAlreadyClosed();
  }

  private async namesFor(employeeIds: string[]): Promise<Map<string, string>> {
    if (employeeIds.length === 0) return new Map();

    const employees = await this.prisma.employee.findMany({
      where: { id: { in: employeeIds } },
      select: { id: true, fullName: true },
    });

    return new Map(employees.map((e) => [e.id, e.fullName]));
  }

  /** Период с начислениями в том виде, в каком его ждёт клиент. */
  private async presentPeriod(periodId: string) {
    const period = await this.prisma.payrollPeriod.findFirstOrThrow({
      where: { id: periodId },
      include: {
        entries: {
          include: { employee: { select: { id: true, fullName: true } } },
          orderBy: { toPay: 'desc' },
        },
      },
    });

    return {
      periodId: period.id,
      periodStart: toIsoDate(period.periodStart),
      periodEnd: toIsoDate(period.periodEnd),
      status: period.status,
      totalAmount: period.totalAmount.toString(),
      closedAt: period.closedAt,
      entries: period.entries.map((e) => ({
        id: e.id,
        employee: e.employee,
        workAmount: e.workAmount.toString(),
        bonus: e.bonus.toString(),
        deduction: e.deduction.toString(),
        totalAccrued: e.totalAccrued.toString(),
        advancePaid: e.advancePaid.toString(),
        toPay: e.toPay.toString(),
        isPaid: e.isPaid,
      })),
    };
  }
}

/** Дата периода — календарная (@db.Date), время в ней смысла не несёт. */
function toIsoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}
