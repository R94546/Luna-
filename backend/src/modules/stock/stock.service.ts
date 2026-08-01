import { Injectable } from '@nestjs/common';
import { Prisma, StockMovementType } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateMovementDto } from './dto/stock.dto';

/** Типы, увеличивающие остаток. Остальные — уменьшают. */
const INBOUND = new Set<StockMovementType>([
  StockMovementType.PRODUCTION_IN,
  StockMovementType.PURCHASE_IN,
  StockMovementType.RETURN_IN,
]);

@Injectable()
export class StockService {
  constructor(private readonly prisma: PrismaService) {}

  async findMovements(dto: PaginationDto & { productId?: string; type?: StockMovementType }) {
    const where: Prisma.StockMovementWhereInput = {
      ...(dto.productId ? { productId: dto.productId } : {}),
      ...(dto.type ? { type: dto.type } : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.stockMovement.findMany({
        where,
        include: {
          product: { select: { id: true, sku: true, name: true } },
          createdBy: { select: { id: true, fullName: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.stockMovement.count({ where }),
    ]);

    return paginate(items, total, dto);
  }

  /**
   * Единственный способ изменить остаток.
   *
   * Движение и обновление products.stock_quantity происходят в одной
   * транзакции. Отдельно записать одно без другого нельзя — deferred-триггер
   * в БД сверяет их в момент коммита и откатывает расхождение.
   *
   * ADJUSTMENT трактуется иначе остальных: клиент присылает ФАКТИЧЕСКИЙ
   * остаток после пересчёта, дельту считает сервер. Кладовщик считает пары,
   * а не разницу — интерфейс обязан совпадать с реальным действием.
   */
  async createMovement(dto: CreateMovementDto, userId: string) {
    return this.prisma.$transaction(async (tx) => {
      const product = await tx.product.findFirst({
        where: { id: dto.productId, deletedAt: null },
      });

      if (!product) throw Errors.notFound('Mahsulot');

      const delta =
        dto.type === StockMovementType.ADJUSTMENT
          ? dto.quantity - product.stockQuantity
          : INBOUND.has(dto.type)
            ? dto.quantity
            : -dto.quantity;

      if (delta === 0) {
        // CHECK-констрейнт запрещает нулевое движение, да и записывать
        // «инвентаризация ничего не изменила» в журнал незачем.
        return { ...product, movement: null };
      }

      const newBalance = product.stockQuantity + delta;

      if (newBalance < 0) {
        throw Errors.insufficientStock(
          product.id,
          product.name,
          product.stockQuantity,
          dto.quantity,
        );
      }

      const updated = await tx.product.update({
        where: { id: product.id },
        data: { stockQuantity: newBalance },
      });

      const movement = await tx.stockMovement.create({
        data: {
          companyId: product.companyId,
          productId: product.id,
          type: dto.type,
          quantity: delta,
          balanceAfter: newBalance,
          note: dto.note,
          refType: 'manual',
          createdById: userId,
        },
      });

      return { ...updated, movement };
    });
  }

  /**
   * Списание/зачисление из других модулей (продажи, заказы, возвраты).
   * Принимает внешний транзакционный клиент: продажа обязана менять склад
   * и кассу в ОДНОЙ транзакции, поэтому свою здесь открывать нельзя.
   */
  async applyMovement(
    tx: Prisma.TransactionClient,
    params: {
      companyId: string;
      productId: string;
      type: StockMovementType;
      quantity: number;
      refType: string;
      refId: string;
      userId?: string;
    },
  ) {
    const product = await tx.product.findFirst({
      where: { id: params.productId, companyId: params.companyId, deletedAt: null },
    });

    if (!product) throw Errors.notFound('Mahsulot');

    const delta = INBOUND.has(params.type) ? params.quantity : -params.quantity;
    const newBalance = product.stockQuantity + delta;

    if (newBalance < 0) {
      throw Errors.insufficientStock(
        product.id,
        product.name,
        product.stockQuantity,
        params.quantity,
      );
    }

    await tx.product.update({
      where: { id: product.id },
      data: { stockQuantity: newBalance },
    });

    return tx.stockMovement.create({
      data: {
        companyId: params.companyId,
        productId: params.productId,
        type: params.type,
        quantity: delta,
        balanceAfter: newBalance,
        refType: params.refType,
        refId: params.refId,
        createdById: params.userId,
      },
    });
  }
}
