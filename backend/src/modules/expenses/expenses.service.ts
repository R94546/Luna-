import { Injectable } from '@nestjs/common';
import { CashCategory, CashDirection, Prisma } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CashService } from '../cash/cash.service';
import {
  CreateCategoryDto,
  CreateExpenseDto,
  ListExpensesDto,
  UpdateExpenseDto,
} from './dto/expense.dto';

const REF_TYPE = 'expense';

@Injectable()
export class ExpensesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly cash: CashService,
  ) {}

  // ── Категории ────────────────────────────────────────────────────────────

  /**
   * Категории расходов.
   *
   * Зарплаты среди них нет и быть не может: она попадает в кассу только
   * через `/salary-payments`, вместе с записью в ведомость. Заведи категорию
   * «Зарплата» — и те же деньги посчитаются дважды, в расходах и в выплатах.
   */
  async findAllCategories() {
    const categories = await this.prisma.expenseCategory.findMany({
      where: { deletedAt: null },
      orderBy: [{ isSystem: 'desc' }, { name: 'asc' }],
    });

    return categories.map((c) => ({
      id: c.id,
      name: c.name,
      color: c.color,
      isSystem: c.isSystem,
    }));
  }

  async createCategory(dto: CreateCategoryDto) {
    const existing = await this.prisma.expenseCategory.findFirst({
      where: { name: dto.name, deletedAt: null },
    });
    if (existing) throw Errors.duplicate('name');

    const created = await this.prisma.expenseCategory.create({
      data: { companyId: requireTenant().companyId, name: dto.name, color: dto.color },
    });

    return { id: created.id, name: created.name, color: created.color, isSystem: false };
  }

  // ── Расходы ──────────────────────────────────────────────────────────────

  async findAll(dto: ListExpensesDto & PaginationDto) {
    const where = this.buildWhere(dto);

    const [items, total, sum] = await Promise.all([
      this.prisma.expense.findMany({
        where,
        include: {
          category: { select: { id: true, name: true, color: true } },
          cashTransaction: { select: { accountId: true } },
        },
        orderBy: [{ spentAt: 'desc' }, { createdAt: 'desc' }],
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.expense.count({ where }),
      this.prisma.expense.aggregate({ where, _sum: { amount: true } }),
    ]);

    return {
      ...paginate(items.map((e) => this.toPublic(e)), total, dto),
      summary: { totalAmount: (sum._sum.amount ?? new Prisma.Decimal(0)).toString() },
    };
  }

  async findOne(id: string) {
    const expense = await this.prisma.expense.findFirst({
      where: { id },
      include: {
        category: { select: { id: true, name: true, color: true } },
        cashTransaction: { select: { accountId: true } },
      },
    });

    if (!expense) throw Errors.notFound('Xarajat');
    return this.toPublic(expense);
  }

  /**
   * Расход.
   *
   * Как и выплата зарплаты, заводится одной транзакцией вместе с движением
   * по кассе: расход, не отражённый в кассе, — это деньги, которые по учёту
   * на месте, а фактически потрачены.
   */
  async create(dto: CreateExpenseDto, userId?: string) {
    const { companyId } = requireTenant();

    const [category, account] = await Promise.all([
      this.prisma.expenseCategory.findFirst({ where: { id: dto.categoryId, deletedAt: null } }),
      this.prisma.cashAccount.findFirst({ where: { id: dto.cashAccountId, isActive: true } }),
    ]);

    if (!category) throw Errors.notFound('Xarajat turi');
    if (!account) throw Errors.notFound('Kassa');

    const amount = new Prisma.Decimal(dto.amount);
    const spentAt = new Date(dto.spentAt);

    const id = await this.prisma.$transaction(async (tx) => {
      const expense = await tx.expense.create({
        data: {
          companyId,
          categoryId: category.id,
          amount,
          spentAt,
          note: dto.note,
          createdById: userId,
        },
      });

      const transactionId = await this.cash.recordMovement(tx, {
        accountId: account.id,
        direction: CashDirection.OUT,
        category: CashCategory.EXPENSE,
        amount,
        occurredAt: spentAt,
        refType: REF_TYPE,
        refId: expense.id,
        note: dto.note ?? category.name,
        userId,
      });

      await tx.expense.update({
        where: { id: expense.id },
        data: { cashTransactionId: transactionId },
      });

      return expense.id;
    });

    return this.findOne(id);
  }

  /**
   * Правка расхода.
   *
   * Изменение суммы обязано доехать до кассы: иначе журнал покажет одно,
   * а список расходов другое. Проще всего было бы обновить обе записи
   * по отдельности — и разойтись при первой же ошибке между ними.
   */
  async update(id: string, dto: UpdateExpenseDto) {
    const expense = await this.prisma.expense.findFirst({ where: { id } });
    if (!expense) throw Errors.notFound('Xarajat');

    if (dto.categoryId) {
      const category = await this.prisma.expenseCategory.findFirst({
        where: { id: dto.categoryId, deletedAt: null },
      });
      if (!category) throw Errors.notFound('Xarajat turi');
    }

    const amount = dto.amount !== undefined ? new Prisma.Decimal(dto.amount) : expense.amount;
    const spentAt = dto.spentAt ? new Date(dto.spentAt) : expense.spentAt;

    await this.prisma.$transaction(async (tx) => {
      await tx.expense.update({
        where: { id },
        data: {
          ...(dto.categoryId ? { categoryId: dto.categoryId } : {}),
          ...(dto.amount !== undefined ? { amount } : {}),
          ...(dto.spentAt ? { spentAt } : {}),
          ...(dto.note !== undefined ? { note: dto.note } : {}),
        },
      });

      if (!expense.cashTransactionId) return;

      const transaction = await tx.cashTransaction.findFirst({
        where: { id: expense.cashTransactionId },
      });
      if (!transaction) return;

      await tx.cashTransaction.update({
        where: { id: transaction.id },
        data: { amount, occurredAt: spentAt, ...(dto.note !== undefined ? { note: dto.note } : {}) },
      });

      // На баланс идёт разница, а не новая сумма: касса двигается ровно
      // на величину правки, и параллельная операция по ней не потеряется.
      const delta = amount.minus(expense.amount);

      if (!delta.isZero()) {
        await tx.cashAccount.update({
          where: { id: transaction.accountId },
          data: { balance: { decrement: delta } },
        });
      }
    });

    return this.findOne(id);
  }

  /**
   * Удаление расхода вместе с его движением по кассе.
   *
   * Здесь именно удаление, а не сторно обратной проводкой, как у продаж:
   * продажа — документ перед покупателем, её история переписываться не
   * должна, а расход почти всегда удаляют потому, что ошиблись при вводе,
   * и вторая строка в журнале только мешала бы сверке. Право оставлено
   * владельцу.
   */
  async remove(id: string) {
    const expense = await this.prisma.expense.findFirst({ where: { id } });
    if (!expense) throw Errors.notFound('Xarajat');

    await this.prisma.$transaction(async (tx) => {
      // Сначала снимаем ссылку: внешний ключ не даст удалить транзакцию,
      // пока расход на неё смотрит.
      await tx.expense.update({ where: { id }, data: { cashTransactionId: null } });

      if (expense.cashTransactionId) {
        await this.cash.reverseMovement(tx, expense.cashTransactionId);
      }

      await tx.expense.delete({ where: { id } });
    });

    return { id, deleted: true };
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  private buildWhere(dto: ListExpensesDto): Prisma.ExpenseWhereInput {
    return {
      ...(dto.categoryId ? { categoryId: dto.categoryId } : {}),
      ...(dto.dateFrom || dto.dateTo
        ? {
            spentAt: {
              ...(dto.dateFrom ? { gte: new Date(dto.dateFrom) } : {}),
              ...(dto.dateTo ? { lte: new Date(dto.dateTo) } : {}),
            },
          }
        : {}),
    };
  }

  private toPublic<
    T extends { amount: Prisma.Decimal; cashTransaction: { accountId: string } | null },
  >(expense: T) {
    const { cashTransaction, ...rest } = expense;
    return {
      ...rest,
      amount: expense.amount.toString(),
      cashAccountId: cashTransaction?.accountId ?? null,
    };
  }
}
