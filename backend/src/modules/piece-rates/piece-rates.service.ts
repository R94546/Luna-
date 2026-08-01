import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreatePieceRateDto, ResolveRateDto } from './dto/piece-rate.dto';

@Injectable()
export class PieceRatesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(filter: { operationId?: string; productId?: string; employeeId?: string }) {
    return this.prisma.pieceRate.findMany({
      where: {
        validTo: null, // только действующие
        ...(filter.operationId ? { operationId: filter.operationId } : {}),
        ...(filter.productId ? { productId: filter.productId } : {}),
        ...(filter.employeeId ? { employeeId: filter.employeeId } : {}),
      },
      include: {
        operation: { select: { id: true, name: true } },
        product: { select: { id: true, sku: true, name: true } },
        employee: { select: { id: true, fullName: true } },
      },
      orderBy: [{ operationId: 'asc' }, { createdAt: 'desc' }],
    });
  }

  /**
   * Новая расценка закрывает предыдущую вместо того, чтобы её перезаписать.
   *
   * История нужна не ради аудита: старые work_logs хранят собственную копию
   * ставки, и если бы расценки правились на месте, то расчёт зарплаты
   * за прошлый месяц и её обоснование в отчёте перестали бы сходиться.
   */
  async create(dto: CreatePieceRateDto) {
    const today = new Date();

    return this.prisma.$transaction(async (tx) => {
      const previous = await tx.pieceRate.findFirst({
        where: {
          operationId: dto.operationId,
          productId: dto.productId ?? null,
          employeeId: dto.employeeId ?? null,
          validTo: null,
        },
      });

      if (previous) {
        await tx.pieceRate.update({
          where: { id: previous.id },
          data: { validTo: today },
        });
      }

      return tx.pieceRate.create({
        data: {
          companyId: requireTenant().companyId,
          operationId: dto.operationId,
          productId: dto.productId,
          employeeId: dto.employeeId,
          rate: dto.rate,
          validFrom: today,
        },
      });
    });
  }

  async remove(id: string) {
    const rate = await this.prisma.pieceRate.findFirst({ where: { id, validTo: null } });
    if (!rate) throw Errors.notFound('Narx');

    return this.prisma.pieceRate.update({
      where: { id },
      data: { validTo: new Date() },
    });
  }

  /**
   * Разрешение ставки от частного к общему:
   *   1. (product, operation, employee) — персональная ставка мастера на модель
   *   2. (product, operation, —)        — ставка по модели
   *   3. (—,       operation, —)        — базовая ставка операции
   *
   * Сортировка по «заполненности» полей делает выбор однозначным без
   * трёх последовательных запросов.
   */
  async resolveRate(dto: ResolveRateDto): Promise<Prisma.Decimal> {
    const onDate = dto.date ? new Date(dto.date) : new Date();

    // Три независимых условия «или конкретное значение, или NULL» —
    // каждое отдельным элементом AND. Класть их в один объект нельзя:
    // повторный ключ OR перезаписал бы предыдущий ещё до Prisma.
    const candidates = await this.prisma.pieceRate.findMany({
      where: {
        operationId: dto.operationId,
        validFrom: { lte: onDate },
        AND: [
          { OR: [{ productId: dto.productId ?? null }, { productId: null }] },
          { OR: [{ employeeId: dto.employeeId ?? null }, { employeeId: null }] },
          { OR: [{ validTo: null }, { validTo: { gte: onDate } }] },
        ],
      },
    });

    const best = candidates.sort((a, b) => {
      const score = (r: typeof a) => (r.employeeId ? 2 : 0) + (r.productId ? 1 : 0);
      return score(b) - score(a);
    })[0];

    if (!best) {
      const operation = await this.prisma.operation.findFirst({
        where: { id: dto.operationId },
        select: { name: true },
      });
      throw Errors.rateNotFound(operation?.name ?? '');
    }

    return best.rate;
  }
}
