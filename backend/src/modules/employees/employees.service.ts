import { Injectable } from '@nestjs/common';
import { Prisma, WorkLogStatus } from '@prisma/client';
import { randomInt } from 'node:crypto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto';

/**
 * Алфавит кода привязки: без 0/O и 1/I/L — код диктуют голосом
 * через шумный цех, и похожие символы гарантированно перепутают.
 */
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 6;
const CODE_TTL_HOURS = 24;

@Injectable()
export class EmployeesService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(filter: { isActive?: boolean; search?: string }) {
    const employees = await this.prisma.employee.findMany({
      where: {
        deletedAt: null,
        ...(filter.isActive === undefined ? {} : { isActive: filter.isActive }),
        ...(filter.search
          ? { fullName: { contains: filter.search, mode: 'insensitive' } }
          : {}),
      },
      include: { defaultOperation: { select: { id: true, name: true } } },
      orderBy: { fullName: 'asc' },
    });

    return employees.map((e) => this.toPublic(e));
  }

  async findOne(id: string) {
    const employee = await this.prisma.employee.findFirst({
      where: { id, deletedAt: null },
      include: { defaultOperation: { select: { id: true, name: true } } },
    });

    if (!employee) throw Errors.notFound('Xodim');
    return this.toPublic(employee);
  }

  create(dto: CreateEmployeeDto) {
    return this.prisma.employee
      .create({ data: { ...dto, companyId: requireTenant().companyId } })
      .then((e) => this.toPublic(e));
  }

  async update(id: string, dto: UpdateEmployeeDto) {
    await this.findOne(id);
    const updated = await this.prisma.employee.update({ where: { id }, data: dto });
    return this.toPublic(updated);
  }

  /**
   * Увольнение. Telegram отвязывается сразу — иначе бывший сотрудник
   * продолжит слать отчёты о выработке и получать за них начисления.
   */
  async remove(id: string) {
    await this.findOne(id);

    const updated = await this.prisma.employee.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        isActive: false,
        telegramUserId: null,
        telegramLinkedAt: null,
      },
    });

    return this.toPublic(updated);
  }

  /**
   * Код привязки Telegram: 6 символов, одноразовый, живёт сутки.
   *
   * Старые неиспользованные коды этого сотрудника гасим — иначе выданный
   * вчера и подсмотренный кем-то код останется рабочим.
   */
  async createLinkCode(employeeId: string, botUsername: string) {
    const employee = await this.prisma.employee.findFirst({
      where: { id: employeeId, deletedAt: null },
    });

    if (!employee) throw Errors.notFound('Xodim');
    if (employee.telegramUserId) throw Errors.telegramAlreadyLinked();

    await this.prisma.telegramLinkCode.updateMany({
      where: { employeeId, usedAt: null },
      data: { usedAt: new Date() },
    });

    const code = this.generateCode();
    const expiresAt = new Date(Date.now() + CODE_TTL_HOURS * 3_600_000);

    await this.prisma.telegramLinkCode.create({
      data: { companyId: employee.companyId, employeeId, code, expiresAt },
    });

    const deepLink = `https://t.me/${botUsername}?start=${code}`;

    return { code, deepLink, qrData: deepLink, expiresAt };
  }

  async unlinkTelegram(employeeId: string) {
    await this.findOne(employeeId);

    const updated = await this.prisma.employee.update({
      where: { id: employeeId },
      data: { telegramUserId: null, telegramUsername: null, telegramLinkedAt: null },
    });

    return this.toPublic(updated);
  }

  /**
   * Выработка и заработок за период.
   *
   * byDay и byProduct отдаются уже сгруппированными — клиент рисует график,
   * а не агрегирует данные сам. Иначе одни и те же суммы на разных экранах
   * начнут расходиться из-за разной логики округления.
   */
  async stats(employeeId: string, dateFrom: string, dateTo: string) {
    const employee = await this.findOne(employeeId);

    const from = new Date(dateFrom);
    const to = new Date(dateTo);

    const where: Prisma.WorkLogWhereInput = {
      employeeId,
      workDate: { gte: from, lte: to },
    };

    const [approved, pending, byProductRaw, byDayRaw, advances] = await Promise.all([
      this.prisma.workLog.aggregate({
        where: { ...where, status: WorkLogStatus.APPROVED },
        _sum: { quantity: true, amount: true },
      }),
      this.prisma.workLog.aggregate({
        where: { ...where, status: WorkLogStatus.PENDING },
        _sum: { quantity: true, amount: true },
      }),
      this.prisma.workLog.groupBy({
        by: ['productId'],
        where: { ...where, status: WorkLogStatus.APPROVED },
        _sum: { quantity: true, amount: true },
      }),
      this.prisma.workLog.groupBy({
        by: ['workDate'],
        where: { ...where, status: WorkLogStatus.APPROVED },
        _sum: { quantity: true, amount: true },
        orderBy: { workDate: 'asc' },
      }),
      this.prisma.salaryPayment.aggregate({
        where: { employeeId, paidAt: { gte: from, lte: to } },
        _sum: { amount: true },
      }),
    ]);

    const products = await this.prisma.product.findMany({
      where: { id: { in: byProductRaw.map((r) => r.productId) } },
      select: { id: true, sku: true, name: true },
    });
    const productById = new Map(products.map((p) => [p.id, p]));

    const totalAmount = approved._sum.amount ?? new Prisma.Decimal(0);
    const advancePaid = advances._sum.amount ?? new Prisma.Decimal(0);

    return {
      employee: { id: employee.id, fullName: employee.fullName },
      period: { from: dateFrom, to: dateTo },
      totalUnits: approved._sum.quantity ?? 0,
      totalAmount: totalAmount.toString(),
      pendingUnits: pending._sum.quantity ?? 0,
      pendingAmount: (pending._sum.amount ?? new Prisma.Decimal(0)).toString(),
      advancePaid: advancePaid.toString(),
      toPay: totalAmount.minus(advancePaid).toString(),
      byProduct: byProductRaw.map((r) => ({
        productId: r.productId,
        productName: productById.get(r.productId)?.name ?? '',
        sku: productById.get(r.productId)?.sku ?? '',
        units: r._sum.quantity ?? 0,
        amount: (r._sum.amount ?? new Prisma.Decimal(0)).toString(),
      })),
      byDay: byDayRaw.map((r) => ({
        date: r.workDate.toISOString().slice(0, 10),
        units: r._sum.quantity ?? 0,
        amount: (r._sum.amount ?? new Prisma.Decimal(0)).toString(),
      })),
    };
  }

  private generateCode(): string {
    let code = '';
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
    }
    return code;
  }

  /**
   * BigInt из telegram_user_id не сериализуется в JSON — JSON.stringify
   * на нём падает с TypeError. Отдаём флагом: клиенту сам ID не нужен.
   */
  private toPublic<T extends { telegramUserId: bigint | null }>(employee: T) {
    const { telegramUserId, ...rest } = employee;
    return { ...rest, telegramLinked: telegramUserId !== null };
  }
}
