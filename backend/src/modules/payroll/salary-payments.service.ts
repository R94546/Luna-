import { Injectable } from '@nestjs/common';
import { CashCategory, CashDirection, Prisma, SalaryPaymentType } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateSalaryPaymentDto, ListSalaryPaymentsDto } from './dto/payroll.dto';
import { PayrollService } from './payroll.service';

/** Полиморфная ссылка в денежном журнале — на что именно потратили. */
const REF_TYPE = 'salary_payment';

@Injectable()
export class SalaryPaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly payroll: PayrollService,
  ) {}

  async findAll(dto: ListSalaryPaymentsDto & PaginationDto) {
    const where: Prisma.SalaryPaymentWhereInput = {
      ...(dto.employeeId ? { employeeId: dto.employeeId } : {}),
      ...(dto.type ? { type: dto.type } : {}),
      ...(dto.dateFrom || dto.dateTo
        ? {
            paidAt: {
              ...(dto.dateFrom ? { gte: new Date(dto.dateFrom) } : {}),
              ...(dto.dateTo ? { lte: new Date(dto.dateTo) } : {}),
            },
          }
        : {}),
    };

    const [items, total, sum] = await Promise.all([
      this.prisma.salaryPayment.findMany({
        where,
        include: {
          employee: { select: { id: true, fullName: true } },
          cashTransaction: { select: { accountId: true } },
        },
        orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.salaryPayment.count({ where }),
      this.prisma.salaryPayment.aggregate({ where, _sum: { amount: true } }),
    ]);

    return {
      ...paginate(items.map((p) => this.toPublic(p)), total, dto),
      summary: { totalAmount: (sum._sum.amount ?? new Prisma.Decimal(0)).toString() },
    };
  }

  /**
   * Выплата денег сотруднику.
   *
   * Единственный путь, которым зарплата попадает в кассу. Отдельной
   * «ручной операции по кассе» для зарплаты нет и быть не должно: она
   * позволила бы записать выплату дважды — в журнал выплат и в кассу —
   * или не записать вовсе.
   *
   * Всё одной транзакцией: сама выплата, движение по кассе, баланс кассы
   * и пересчёт начисления. Разорви любое звено — и ведомость перестанет
   * сходиться с деньгами в ящике.
   */
  async create(dto: CreateSalaryPaymentDto, userId?: string) {
    const { companyId } = requireTenant();
    const amount = new Prisma.Decimal(dto.amount);
    const paidAt = new Date(dto.paidAt);

    const [employee, account] = await Promise.all([
      this.prisma.employee.findFirst({ where: { id: dto.employeeId, deletedAt: null } }),
      this.prisma.cashAccount.findFirst({ where: { id: dto.cashAccountId, isActive: true } }),
    ]);

    if (!employee) throw Errors.notFound('Xodim');
    if (!account) throw Errors.notFound('Kassa');

    const paymentId = await this.prisma.$transaction(async (tx) => {
      const entryId = await this.payroll.findEntryForPayment(
        tx,
        dto.employeeId,
        paidAt,
        dto.payrollEntryId,
      );

      const payment = await tx.salaryPayment.create({
        data: {
          companyId,
          employeeId: dto.employeeId,
          payrollEntryId: entryId,
          type: dto.type,
          amount,
          paidAt,
          note: dto.note,
          createdById: userId,
        },
      });

      const transaction = await tx.cashTransaction.create({
        data: {
          companyId,
          accountId: account.id,
          direction: CashDirection.OUT,
          category: CashCategory.SALARY,
          amount,
          refType: REF_TYPE,
          refId: payment.id,
          occurredAt: paidAt,
          note: dto.note ?? this.defaultNote(dto.type, employee.fullName),
          createdById: userId,
        },
      });

      await tx.salaryPayment.update({
        where: { id: payment.id },
        data: { cashTransactionId: transaction.id },
      });

      // Баланс денормализован ради сводки по кассе; decrement — атомарный
      // инкремент на стороне БД, две одновременные выплаты не затрут
      // изменения друг друга.
      await tx.cashAccount.update({
        where: { id: account.id },
        data: { balance: { decrement: amount } },
      });

      if (entryId) {
        await this.payroll.refreshEntryAfterPayment(tx, entryId);
        await this.markPaidIfSettled(tx, entryId);
      }

      return payment.id;
    });

    return this.findOne(paymentId);
  }

  async findOne(id: string) {
    const payment = await this.prisma.salaryPayment.findFirst({
      where: { id },
      include: {
        employee: { select: { id: true, fullName: true } },
        cashTransaction: { select: { accountId: true } },
      },
    });

    if (!payment) throw Errors.notFound("To'lov");
    return this.toPublic(payment);
  }

  /**
   * Начисление считается закрытым, когда выплачено не меньше начисленного.
   *
   * Сравнение «не меньше», а не «равно»: округление при выдаче наличными
   * в большую сторону — обычное дело, и оставлять из-за пятисот сумов
   * запись незакрытой значит завести вечный хвост в ведомости.
   */
  private async markPaidIfSettled(tx: Prisma.TransactionClient, entryId: string) {
    const entry = await tx.payrollEntry.findFirstOrThrow({ where: { id: entryId } });

    const paid = await tx.salaryPayment.aggregate({
      where: { payrollEntryId: entryId },
      _sum: { amount: true },
    });

    const total = paid._sum.amount ?? new Prisma.Decimal(0);
    const settled = total.gte(entry.totalAccrued) && entry.totalAccrued.gt(0);

    if (settled !== entry.isPaid) {
      await tx.payrollEntry.update({ where: { id: entryId }, data: { isPaid: settled } });
    }
  }

  private defaultNote(type: SalaryPaymentType, fullName: string): string {
    const label: Record<SalaryPaymentType, string> = {
      ADVANCE: 'Avans',
      SALARY: 'Oylik',
      BONUS: 'Mukofot',
    };
    return `${label[type]} — ${fullName}`;
  }

  private toPublic<T extends { amount: Prisma.Decimal; cashTransaction: { accountId: string } | null }>(
    payment: T,
  ) {
    const { cashTransaction, ...rest } = payment;
    return {
      ...rest,
      amount: payment.amount.toString(),
      cashAccountId: cashTransaction?.accountId ?? null,
    };
  }
}
