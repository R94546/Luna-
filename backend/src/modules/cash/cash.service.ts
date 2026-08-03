import { Injectable } from '@nestjs/common';
import { CashCategory, CashDirection, Prisma } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import {
  CreateAccountDto,
  CreateTransactionDto,
  ListTransactionsDto,
  SummaryDto,
} from './dto/cash.dto';

const ZERO = new Prisma.Decimal(0);

/** Движение денег: всё, что нужно записать в журнал и отразить на балансе. */
export interface MovementInput {
  accountId: string;
  direction: CashDirection;
  category: CashCategory;
  amount: Prisma.Decimal;
  occurredAt: Date;
  /** 'sale' | 'expense' | 'salary_payment' | 'manual' */
  refType: string;
  refId?: string;
  note?: string;
  userId?: string;
}

/** Человеческие названия для сводки — категории приходят из enum'а. */
const CATEGORY_NAMES: Record<CashCategory, string> = {
  SALE: 'Savdo',
  EXPENSE: 'Xarajat',
  SALARY: 'Ish haqi',
  INVESTMENT: 'Kirim (egasidan)',
  WITHDRAWAL: 'Chiqim (egasiga)',
  TRANSFER: "O'tkazma",
  OTHER: 'Boshqa',
};

@Injectable()
export class CashService {
  constructor(private readonly prisma: PrismaService) {}

  // ── Кассы ────────────────────────────────────────────────────────────────

  async findAllAccounts() {
    const accounts = await this.prisma.cashAccount.findMany({
      where: { isActive: true },
      orderBy: [{ isDefault: 'desc' }, { name: 'asc' }],
    });

    return accounts.map((a) => this.toPublicAccount(a));
  }

  /**
   * Заведение кассы.
   *
   * Стартовый остаток проводится через журнал операцией INVESTMENT, а не
   * записывается в баланс напрямую: иначе сводка за период не сойдётся —
   * деньги в кассе есть, а движения, которым они появились, нет.
   */
  async createAccount(dto: CreateAccountDto, userId?: string) {
    const { companyId } = requireTenant();

    const existing = await this.prisma.cashAccount.findFirst({ where: { name: dto.name } });
    if (existing) throw Errors.duplicate('name');

    const account = await this.prisma.$transaction(async (tx) => {
      if (dto.isDefault) await this.clearDefaultFlag(tx);

      const created = await tx.cashAccount.create({
        data: {
          companyId,
          name: dto.name,
          type: dto.type,
          isDefault: dto.isDefault,
        },
      });

      if (dto.balance) {
        await this.recordMovement(tx, {
          accountId: created.id,
          direction: CashDirection.IN,
          category: CashCategory.INVESTMENT,
          amount: new Prisma.Decimal(dto.balance),
          occurredAt: new Date(),
          refType: 'manual',
          note: "Kassa ochilishidagi qoldiq",
          userId,
        });
      }

      return tx.cashAccount.findFirstOrThrow({ where: { id: created.id } });
    });

    return this.toPublicAccount(account);
  }

  // ── Журнал ───────────────────────────────────────────────────────────────

  async findAllTransactions(dto: ListTransactionsDto & PaginationDto) {
    const where = this.buildTransactionWhere(dto);

    const [items, total] = await Promise.all([
      this.prisma.cashTransaction.findMany({
        where,
        include: { account: { select: { id: true, name: true } } },
        orderBy: [{ occurredAt: 'desc' }, { createdAt: 'desc' }],
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.cashTransaction.count({ where }),
    ]);

    const totals = await this.sumByDirection(where);

    return {
      ...paginate(
        items.map((t) => ({
          id: t.id,
          account: t.account,
          direction: t.direction,
          category: t.category,
          categoryName: CATEGORY_NAMES[t.category],
          amount: t.amount.toString(),
          refType: t.refType,
          refId: t.refId,
          occurredAt: t.occurredAt,
          note: t.note,
        })),
        total,
        dto,
      ),
      summary: {
        income: totals.income.toString(),
        outcome: totals.outcome.toString(),
        net: totals.income.minus(totals.outcome).toString(),
      },
    };
  }

  /**
   * Ручная операция: владелец внёс свои деньги или забрал выручку.
   *
   * Категории продажи, зарплаты и расхода здесь запрещены на уровне схемы
   * валидации — у каждой есть свой эндпоинт, который заводит первичный
   * документ вместе с движением. Иначе в кассе появилась бы зарплата,
   * которой не соответствует ни одна выплата.
   */
  async createTransaction(dto: CreateTransactionDto, userId?: string) {
    const account = await this.prisma.cashAccount.findFirst({
      where: { id: dto.accountId, isActive: true },
    });
    if (!account) throw Errors.notFound('Kassa');

    const id = await this.prisma.$transaction((tx) =>
      this.recordMovement(tx, {
        accountId: account.id,
        direction: dto.direction,
        category: dto.category,
        amount: new Prisma.Decimal(dto.amount),
        occurredAt: new Date(dto.occurredAt),
        refType: 'manual',
        note: dto.note,
        userId,
      }),
    );

    const created = await this.prisma.cashTransaction.findFirstOrThrow({
      where: { id },
      include: { account: { select: { id: true, name: true } } },
    });

    return {
      id: created.id,
      account: created.account,
      direction: created.direction,
      category: created.category,
      amount: created.amount.toString(),
      occurredAt: created.occurredAt,
      note: created.note,
    };
  }

  // ── Сводка ───────────────────────────────────────────────────────────────

  /**
   * Сводка за период.
   *
   * Остаток на конец считается от текущих балансов назад, а не суммированием
   * журнала вперёд: у кассы может быть остаток, заведённый до появления
   * журнала (демо-данные, миграция со старого учёта), и сумма движений его
   * не воспроизведёт. Текущий баланс — единственная величина, которой можно
   * доверять; всё остальное отсчитывается от неё.
   */
  async summary(dto: SummaryDto) {
    const from = new Date(dto.dateFrom);
    const to = endOfDay(dto.dateTo);

    const [accounts, inPeriod, afterPeriod, expenseRows] = await Promise.all([
      this.prisma.cashAccount.findMany({ where: { isActive: true } }),
      this.prisma.cashTransaction.groupBy({
        by: ['direction', 'category'],
        where: { occurredAt: { gte: from, lte: to } },
        _sum: { amount: true },
      }),
      this.sumByDirection({ occurredAt: { gt: to } }),
      this.expenseBreakdown(from, to),
    ]);

    const currentBalance = accounts.reduce((sum, a) => sum.plus(a.balance), ZERO);
    const closingBalance = currentBalance.minus(afterPeriod.income).plus(afterPeriod.outcome);

    const income = inPeriod.filter((r) => r.direction === CashDirection.IN);
    const outcome = inPeriod.filter((r) => r.direction === CashDirection.OUT);

    const incomeTotal = sumRows(income);
    const outcomeTotal = sumRows(outcome);
    const bySale = sumRows(income.filter((r) => r.category === CashCategory.SALE));

    return {
      dateFrom: dto.dateFrom,
      dateTo: dto.dateTo,
      openingBalance: closingBalance.minus(incomeTotal).plus(outcomeTotal).toString(),
      income: {
        total: incomeTotal.toString(),
        bySale: bySale.toString(),
        other: incomeTotal.minus(bySale).toString(),
      },
      outcome: {
        total: outcomeTotal.toString(),
        // Расходы раскрываются по своим категориям («Аренда», «Коммуналка»),
        // остальное — по категориям журнала. Владельцу нужно видеть, на что
        // именно ушли деньги, а не строку «расходы» на треть оборота.
        byCategory: [
          ...outcome
            .filter((r) => r.category !== CashCategory.EXPENSE)
            .map((r) => ({
              category: r.category,
              name: CATEGORY_NAMES[r.category],
              amount: (r._sum.amount ?? ZERO).toString(),
            })),
          ...expenseRows,
        ].sort((a, b) => Number(b.amount) - Number(a.amount)),
      },
      closingBalance: closingBalance.toString(),
      accounts: accounts.map((a) => this.toPublicAccount(a)),
    };
  }

  // ── Общий механизм движения денег ────────────────────────────────────────

  /**
   * Единственный способ, которым деньги попадают в кассу и уходят из неё.
   *
   * Запись в журнал и изменение баланса — всегда вместе, всегда в одной
   * транзакции вызывающего кода. Пока это одна функция, баланс не может
   * разойтись с журналом: разойтись он мог бы только там, где кто-то
   * обновил `balance` мимо неё.
   *
   * `decrement`/`increment` вместо чтения и записи: две одновременные
   * операции по одной кассе не затрут изменения друг друга.
   */
  async recordMovement(tx: Prisma.TransactionClient, input: MovementInput): Promise<string> {
    const transaction = await tx.cashTransaction.create({
      data: {
        companyId: requireTenant().companyId,
        accountId: input.accountId,
        direction: input.direction,
        category: input.category,
        amount: input.amount,
        refType: input.refType,
        refId: input.refId,
        occurredAt: input.occurredAt,
        note: input.note,
        createdById: input.userId,
      },
    });

    await tx.cashAccount.update({
      where: { id: input.accountId },
      data: {
        balance:
          input.direction === CashDirection.IN
            ? { increment: input.amount }
            : { decrement: input.amount },
      },
    });

    return transaction.id;
  }

  /**
   * Откат движения: удаляет запись журнала и возвращает баланс.
   *
   * Применяется, когда удаляется сам первичный документ (ошибочно заведённый
   * расход). Для продаж откат будет другим — там история не переписывается,
   * а сторнируется обратной проводкой.
   */
  async reverseMovement(tx: Prisma.TransactionClient, transactionId: string): Promise<void> {
    const transaction = await tx.cashTransaction.findFirst({ where: { id: transactionId } });
    if (!transaction) return;

    await tx.cashAccount.update({
      where: { id: transaction.accountId },
      data: {
        balance:
          transaction.direction === CashDirection.IN
            ? { decrement: transaction.amount }
            : { increment: transaction.amount },
      },
    });

    await tx.cashTransaction.delete({ where: { id: transactionId } });
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  private async clearDefaultFlag(tx: Prisma.TransactionClient): Promise<void> {
    await tx.cashAccount.updateMany({ where: { isDefault: true }, data: { isDefault: false } });
  }

  private async sumByDirection(where: Prisma.CashTransactionWhereInput) {
    const rows = await this.prisma.cashTransaction.groupBy({
      by: ['direction'],
      where,
      _sum: { amount: true },
    });

    const of = (direction: CashDirection) =>
      rows.find((r) => r.direction === direction)?._sum.amount ?? ZERO;

    return { income: of(CashDirection.IN), outcome: of(CashDirection.OUT) };
  }

  /** Расходы периода в разрезе своих категорий, а не одной строкой. */
  private async expenseBreakdown(from: Date, to: Date) {
    const grouped = await this.prisma.expense.groupBy({
      by: ['categoryId'],
      where: { spentAt: { gte: from, lte: to } },
      _sum: { amount: true },
    });

    if (grouped.length === 0) return [];

    const categories = await this.prisma.expenseCategory.findMany({
      where: { id: { in: grouped.map((g) => g.categoryId) } },
      select: { id: true, name: true },
    });
    const nameById = new Map(categories.map((c) => [c.id, c.name]));

    return grouped.map((g) => ({
      category: CashCategory.EXPENSE,
      name: nameById.get(g.categoryId) ?? '',
      amount: (g._sum.amount ?? ZERO).toString(),
    }));
  }

  private buildTransactionWhere(dto: ListTransactionsDto): Prisma.CashTransactionWhereInput {
    return {
      ...(dto.accountId ? { accountId: dto.accountId } : {}),
      ...(dto.direction ? { direction: dto.direction } : {}),
      ...(dto.category ? { category: dto.category } : {}),
      ...(dto.dateFrom || dto.dateTo
        ? {
            occurredAt: {
              ...(dto.dateFrom ? { gte: new Date(dto.dateFrom) } : {}),
              ...(dto.dateTo ? { lte: endOfDay(dto.dateTo) } : {}),
            },
          }
        : {}),
    };
  }

  private toPublicAccount(a: {
    id: string;
    name: string;
    type: string;
    balance: Prisma.Decimal;
    isDefault: boolean;
  }) {
    return {
      id: a.id,
      name: a.name,
      type: a.type,
      balance: a.balance.toString(),
      isDefault: a.isDefault,
    };
  }
}

function sumRows(rows: { _sum: { amount: Prisma.Decimal | null } }[]): Prisma.Decimal {
  return rows.reduce((sum, r) => sum.plus(r._sum.amount ?? ZERO), ZERO);
}

/**
 * Границы дня.
 *
 * `occurred_at` — момент времени, а не дата, и фильтр `lte: '2026-08-31'`
 * без этого отсёк бы всё, что произошло в последний день после полуночи.
 */
function endOfDay(isoDate: string): Date {
  return new Date(`${isoDate}T23:59:59.999Z`);
}
