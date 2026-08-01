import { Injectable, Logger } from '@nestjs/common';
import { Prisma, WorkLogSource, WorkLogStatus } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { AppException, Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { PieceRatesService } from '../piece-rates/piece-rates.service';
import { CreateWorkLogDto, ListWorkLogsDto } from './dto/work-log.dto';

/** Данные отчёта из Telegram — приходят уже проверенными ботом. */
export interface TelegramWorkLogInput {
  companyId: string;
  employeeId: string;
  productId: string;
  operationId: string;
  quantity: number;
  telegramMsgId?: number;
}

@Injectable()
export class WorkLogsService {
  private readonly logger = new Logger(WorkLogsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly rates: PieceRatesService,
  ) {}

  async findAll(dto: ListWorkLogsDto & PaginationDto) {
    const where = this.buildWhere(dto);

    const [items, total, summary] = await Promise.all([
      this.prisma.workLog.findMany({
        where,
        include: {
          employee: { select: { id: true, fullName: true } },
          product: { select: { id: true, sku: true, name: true } },
          operation: { select: { id: true, name: true } },
        },
        orderBy: [{ workDate: 'desc' }, { createdAt: 'desc' }],
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.workLog.count({ where }),
      // Итоги считаются по ВСЕЙ выборке с учётом фильтров, а не по странице:
      // владельцу нужна сумма за месяц, а не за 20 видимых строк.
      this.prisma.workLog.aggregate({ where, _sum: { quantity: true, amount: true } }),
    ]);

    return {
      ...paginate(items.map((w) => this.toPublic(w)), total, dto),
      summary: {
        totalQuantity: summary._sum.quantity ?? 0,
        totalAmount: (summary._sum.amount ?? new Prisma.Decimal(0)).toString(),
      },
    };
  }

  findPending(dto: PaginationDto) {
    return this.findAll({ ...dto, status: WorkLogStatus.PENDING });
  }

  async findOne(id: string) {
    const log = await this.prisma.workLog.findFirst({
      where: { id },
      include: {
        employee: { select: { id: true, fullName: true } },
        product: { select: { id: true, sku: true, name: true } },
        operation: { select: { id: true, name: true } },
      },
    });

    if (!log) throw Errors.notFound('Ish yozuvi');
    return this.toPublic(log);
  }

  /**
   * Ручной ввод администратором. Такая запись сразу APPROVED —
   * тот, кто её создаёт, и есть подтверждающий.
   */
  async createManual(dto: CreateWorkLogDto, userId: string) {
    const { companyId } = requireTenant();
    const workDate = new Date(dto.workDate);

    const rate =
      dto.rate !== undefined
        ? new Prisma.Decimal(dto.rate)
        : await this.rates.resolveRate({
            operationId: dto.operationId,
            productId: dto.productId,
            employeeId: dto.employeeId,
            date: dto.workDate,
          });

    const created = await this.prisma.workLog.create({
      data: {
        companyId,
        employeeId: dto.employeeId,
        productId: dto.productId,
        operationId: dto.operationId,
        quantity: dto.quantity,
        rate,
        amount: rate.mul(dto.quantity),
        workDate,
        status: WorkLogStatus.APPROVED,
        source: WorkLogSource.MANUAL,
        note: dto.note,
        approvedById: userId,
        approvedAt: new Date(),
      },
      include: {
        employee: { select: { id: true, fullName: true } },
        product: { select: { id: true, sku: true, name: true } },
        operation: { select: { id: true, name: true } },
      },
    });

    return this.toPublic(created);
  }

  /**
   * Запись из Telegram.
   *
   * Статус зависит от настройки компании: при work_log_auto_approve отчёт
   * сразу идёт в зарплату, иначе ждёт мастера. Ставка фиксируется здесь же
   * и больше не пересчитывается — повышение расценок не должно задним
   * числом менять уже начисленное.
   */
  async createFromTelegram(input: TelegramWorkLogInput) {
    const company = await this.prisma.company.findUniqueOrThrow({
      where: { id: input.companyId },
      select: { workLogAutoApprove: true },
    });

    const rate = await this.rates.resolveRate({
      operationId: input.operationId,
      productId: input.productId,
      employeeId: input.employeeId,
    });

    const workDate = new Date();
    workDate.setUTCHours(0, 0, 0, 0);

    const created = await this.prisma.workLog.create({
      data: {
        companyId: input.companyId,
        employeeId: input.employeeId,
        productId: input.productId,
        operationId: input.operationId,
        quantity: input.quantity,
        rate,
        amount: rate.mul(input.quantity),
        workDate,
        status: company.workLogAutoApprove ? WorkLogStatus.APPROVED : WorkLogStatus.PENDING,
        source: WorkLogSource.TELEGRAM,
        telegramMsgId: input.telegramMsgId,
        approvedAt: company.workLogAutoApprove ? new Date() : null,
      },
      include: {
        product: { select: { name: true, sku: true } },
        operation: { select: { name: true } },
      },
    });

    return created;
  }

  async approve(id: string, userId: string) {
    const log = await this.prisma.workLog.findFirst({ where: { id } });
    if (!log) throw Errors.notFound('Ish yozuvi');
    if (log.status !== WorkLogStatus.PENDING) throw Errors.workLogNotPending();

    const updated = await this.prisma.workLog.update({
      where: { id },
      data: { status: WorkLogStatus.APPROVED, approvedById: userId, approvedAt: new Date() },
    });

    return this.toPublic(updated);
  }

  async reject(id: string, userId: string, reason?: string) {
    const log = await this.prisma.workLog.findFirst({ where: { id } });
    if (!log) throw Errors.notFound('Ish yozuvi');
    if (log.status !== WorkLogStatus.PENDING) throw Errors.workLogNotPending();

    const updated = await this.prisma.workLog.update({
      where: { id },
      data: {
        status: WorkLogStatus.REJECTED,
        rejectReason: reason,
        approvedById: userId,
        approvedAt: new Date(),
      },
    });

    return this.toPublic(updated);
  }

  /**
   * Подтверждение пачкой: утром мастер закрывает вчерашние отчёты одним
   * нажатием вместо двадцати тапов.
   *
   * updateMany со статусом PENDING в условии делает операцию безопасной
   * при гонке: запись, подтверждённая другим администратором секунду назад,
   * просто не попадёт под обновление.
   */
  async bulkApprove(ids: string[], userId: string) {
    const result = await this.prisma.workLog.updateMany({
      where: { id: { in: ids }, status: WorkLogStatus.PENDING },
      data: { status: WorkLogStatus.APPROVED, approvedById: userId, approvedAt: new Date() },
    });

    return {
      approved: result.count,
      skipped: ids.length - result.count,
    };
  }

  /**
   * Удалить можно только неподтверждённую запись, не попавшую в зарплату.
   * Подтверждённая — основание для начисления, её удаление разошло бы
   * зарплатный период с фактически выплаченными деньгами.
   */
  async remove(id: string) {
    const log = await this.prisma.workLog.findFirst({ where: { id } });
    if (!log) throw Errors.notFound('Ish yozuvi');

    if (log.payrollEntryId) {
      throw new AppException(422, 'WORK_LOG_IN_PAYROLL', 'error.work_log_in_payroll');
    }

    if (log.status === WorkLogStatus.APPROVED) throw Errors.workLogNotPending();

    return this.prisma.workLog.delete({ where: { id } });
  }

  /** Отмена рабочим своей же записи из Telegram — окно 30 минут. */
  async cancelByEmployee(id: string, employeeId: string): Promise<boolean> {
    const log = await this.prisma.workLog.findFirst({ where: { id, employeeId } });

    if (!log || log.payrollEntryId) return false;

    const ageMinutes = (Date.now() - log.createdAt.getTime()) / 60_000;
    if (ageMinutes > 30) return false;

    await this.prisma.workLog.delete({ where: { id } });
    return true;
  }

  /** Итоги сотрудника за период — для команд бота /today и /month. */
  async employeeSummary(employeeId: string, from: Date, to: Date) {
    const [agg, byProduct] = await Promise.all([
      this.prisma.workLog.aggregate({
        where: {
          employeeId,
          workDate: { gte: from, lte: to },
          status: { in: [WorkLogStatus.APPROVED, WorkLogStatus.PENDING] },
        },
        _sum: { quantity: true, amount: true },
      }),
      this.prisma.workLog.groupBy({
        by: ['productId'],
        where: {
          employeeId,
          workDate: { gte: from, lte: to },
          status: { in: [WorkLogStatus.APPROVED, WorkLogStatus.PENDING] },
        },
        _sum: { quantity: true, amount: true },
      }),
    ]);

    const products = await this.prisma.product.findMany({
      where: { id: { in: byProduct.map((b) => b.productId) } },
      select: { id: true, name: true },
    });
    const nameById = new Map(products.map((p) => [p.id, p.name]));

    return {
      totalQuantity: agg._sum.quantity ?? 0,
      totalAmount: agg._sum.amount ?? new Prisma.Decimal(0),
      byProduct: byProduct.map((b) => ({
        name: nameById.get(b.productId) ?? '',
        quantity: b._sum.quantity ?? 0,
        amount: b._sum.amount ?? new Prisma.Decimal(0),
      })),
    };
  }

  /** Модели, по которым рабочий отчитывался недавно — их бот покажет первыми. */
  async recentProductsFor(employeeId: string, limit = 6) {
    const recent = await this.prisma.workLog.findMany({
      where: { employeeId },
      select: { productId: true },
      orderBy: { createdAt: 'desc' },
      take: 40,
    });

    const seen: string[] = [];
    for (const r of recent) {
      if (!seen.includes(r.productId)) seen.push(r.productId);
      if (seen.length >= limit) break;
    }

    if (seen.length === 0) return [];

    const products = await this.prisma.product.findMany({
      where: { id: { in: seen }, isActive: true, deletedAt: null },
      select: { id: true, name: true, sku: true },
    });

    // Возвращаем в порядке недавности, а не в порядке выдачи БД.
    return seen
      .map((id) => products.find((p) => p.id === id))
      .filter((p): p is NonNullable<typeof p> => Boolean(p));
  }

  private buildWhere(dto: ListWorkLogsDto): Prisma.WorkLogWhereInput {
    return {
      ...(dto.status ? { status: dto.status } : {}),
      ...(dto.employeeId ? { employeeId: dto.employeeId } : {}),
      ...(dto.productId ? { productId: dto.productId } : {}),
      ...(dto.dateFrom || dto.dateTo
        ? {
            workDate: {
              ...(dto.dateFrom ? { gte: new Date(dto.dateFrom) } : {}),
              ...(dto.dateTo ? { lte: new Date(dto.dateTo) } : {}),
            },
          }
        : {}),
    };
  }

  /** BigInt (telegramMsgId) ломает JSON.stringify — отдаём строкой. */
  private toPublic<T extends { telegramMsgId: bigint | null; rate: Prisma.Decimal; amount: Prisma.Decimal }>(
    log: T,
  ) {
    return {
      ...log,
      telegramMsgId: log.telegramMsgId?.toString() ?? null,
      rate: log.rate.toString(),
      amount: log.amount.toString(),
    };
  }
}
