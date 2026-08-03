import { Injectable } from '@nestjs/common';
import { OrderStatus, Prisma, StockMovementType } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { SalesService } from '../sales/sales.service';
import { StockService } from '../stock/stock.service';
import {
  ChangeStatusDto,
  CreateOrderDto,
  ListOrdersDto,
  UpdateOrderDto,
  UpdateProgressDto,
} from './dto/order.dto';
import { availableTransitions, canTransition } from './order-status';

const ZERO = new Prisma.Decimal(0);
const REF_TYPE = 'order';

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stock: StockService,
    private readonly sales: SalesService,
  ) {}

  async findAll(dto: ListOrdersDto & PaginationDto) {
    const where = this.buildWhere(dto);

    const [items, total] = await Promise.all([
      this.prisma.order.findMany({
        where,
        include: this.include(),
        orderBy: [{ createdAt: 'desc' }],
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.order.count({ where }),
    ]);

    return paginate(items.map((o) => this.toPublic(o)), total, dto);
  }

  /** Просроченные — отдельным списком: это то, из-за чего теряют клиентов. */
  findOverdue(dto: PaginationDto) {
    return this.findAll({ ...dto, overdue: true });
  }

  async findOne(id: string) {
    const order = await this.prisma.order.findFirst({ where: { id }, include: this.include() });
    if (!order) throw Errors.notFound('Buyurtma');
    return this.toPublic(order);
  }

  async create(dto: CreateOrderDto, userId?: string) {
    const { companyId } = requireTenant();

    await this.assertProductsExist(dto.items.map((i) => i.productId));

    const items = dto.items.map((i) => {
      const unitPrice = new Prisma.Decimal(i.unitPrice);
      return {
        productId: i.productId,
        quantity: i.quantity,
        unitPrice,
        total: unitPrice.mul(i.quantity),
      };
    });

    const totalAmount = items.reduce((sum, i) => sum.plus(i.total), ZERO);

    const id = await this.prisma.$transaction(async (tx) => {
      const orderNumber = await this.prisma.nextNumber(tx, companyId, 'order');

      const order = await tx.order.create({
        data: {
          companyId,
          orderNumber,
          customerId: dto.customerId,
          dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
          totalAmount,
          prepaidAmount: new Prisma.Decimal(dto.prepaidAmount),
          note: dto.note,
          createdById: userId,
          items: { create: items },
        },
      });

      return order.id;
    });

    return this.findOne(id);
  }

  /**
   * Правка заказа.
   *
   * Позиции меняются только пока заказ не выдан: после выдачи они уже
   * списаны со склада, и правка состава разошла бы движение с документом.
   */
  async update(id: string, dto: UpdateOrderDto) {
    const order = await this.prisma.order.findFirst({ where: { id } });
    if (!order) throw Errors.notFound('Buyurtma');

    if (dto.items && (order.status === OrderStatus.ISSUED || order.status === OrderStatus.CANCELLED)) {
      throw Errors.invalidStatusTransition(order.status, order.status);
    }

    await this.prisma.$transaction(async (tx) => {
      if (dto.items) {
        await this.assertProductsExist(dto.items.map((i) => i.productId));
        await tx.orderItem.deleteMany({ where: { orderId: id } });

        const items = dto.items.map((i) => {
          const unitPrice = new Prisma.Decimal(i.unitPrice);
          return {
            orderId: id,
            productId: i.productId,
            quantity: i.quantity,
            unitPrice,
            total: unitPrice.mul(i.quantity),
          };
        });

        await tx.orderItem.createMany({ data: items });

        await tx.order.update({
          where: { id },
          data: { totalAmount: items.reduce((sum, i) => sum.plus(i.total), ZERO) },
        });
      }

      await tx.order.update({
        where: { id },
        data: {
          ...(dto.customerId ? { customerId: dto.customerId } : {}),
          ...(dto.dueDate ? { dueDate: new Date(dto.dueDate) } : {}),
          ...(dto.note !== undefined ? { note: dto.note } : {}),
        },
      });
    });

    return this.findOne(id);
  }

  /**
   * Отметка о выработке по заказу.
   *
   * Ставится вручную. Вывести её из work_logs нельзя: в схеме у выработки
   * нет ссылки на заказ, и связать «сшили 18 пар Спорт-12» с конкретным
   * заказом, когда их два на одну модель, не по чему.
   */
  async updateProgress(id: string, dto: UpdateProgressDto) {
    const order = await this.prisma.order.findFirst({
      where: { id },
      include: { items: true },
    });
    if (!order) throw Errors.notFound('Buyurtma');

    const known = new Set(order.items.map((i) => i.id));

    await this.prisma.$transaction(async (tx) => {
      for (const item of dto.items) {
        if (!known.has(item.itemId)) throw Errors.notFound('Buyurtma qatori');

        await tx.orderItem.update({
          where: { id: item.itemId },
          data: { producedQuantity: item.producedQuantity },
        });
      }
    });

    return this.findOne(id);
  }

  /**
   * Смена статуса.
   *
   * Переход в ISSUED — единственный, у которого есть последствия за
   * пределами самого заказа: товар уходит со склада, и, если попросили,
   * оформляется продажа. Всё это одной транзакцией с самой сменой статуса:
   * заказ, помеченный выданным, но не списавший товар, — расхождение,
   * которое всплывёт только при инвентаризации.
   */
  async changeStatus(id: string, dto: ChangeStatusDto, userId?: string) {
    const order = await this.prisma.order.findFirst({
      where: { id },
      include: { items: true },
    });
    if (!order) throw Errors.notFound('Buyurtma');

    if (!canTransition(order.status, dto.status)) {
      throw Errors.invalidStatusTransition(order.status, dto.status);
    }

    if (dto.status !== OrderStatus.ISSUED) {
      await this.prisma.order.update({
        where: { id },
        data: {
          status: dto.status,
          ...(dto.reason ? { note: dto.reason } : {}),
        },
      });

      return this.findOne(id);
    }

    // Подготовка продажи — до транзакции: она читает справочники и проверяет
    // кассу, и держать на этом открытую транзакцию незачем.
    const sale = dto.createSale ? await this.prepareSale(order, dto) : null;

    await this.prisma.$transaction(async (tx) => {
      // Товар уходит со склада ровно одним движением на одно физическое
      // событие: либо выдача по заказу, либо продажа. Проводить оба значит
      // списать одну партию дважды.
      for (const item of order.items) {
        await this.stock.applyMovement(tx, {
          companyId: order.companyId,
          productId: item.productId,
          type: sale ? StockMovementType.SALE_OUT : StockMovementType.ORDER_OUT,
          quantity: item.quantity,
          refType: REF_TYPE,
          refId: order.id,
          userId,
        });
      }

      await tx.order.update({
        where: { id },
        data: { status: OrderStatus.ISSUED, issuedAt: new Date() },
      });

      if (sale) await this.sales.createWithin(tx, sale, userId);
    });

    return this.findOne(id);
  }

  async remove(id: string, reason?: string) {
    return this.changeStatus(id, {
      status: OrderStatus.CANCELLED,
      createSale: false,
      paymentMethod: 'CASH',
      reason,
    });
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  /**
   * Продажа по выдаваемому заказу.
   *
   * Позиции и цены берутся из заказа — покупатель платит по тому, о чём
   * договаривались, а не по текущему прайсу. Склад продажа не трогает:
   * движение уже проводит выдача, и `skipStock` не даёт списать дважды.
   */
  private prepareSale(
    order: {
      id: string;
      customerId: string | null;
      prepaidAmount: Prisma.Decimal;
      items: { productId: string; quantity: number; unitPrice: Prisma.Decimal }[];
    },
    dto: ChangeStatusDto,
  ) {
    return this.sales.prepareForIssuedOrder({
      customerId: order.customerId ?? undefined,
      orderId: order.id,
      paymentMethod: dto.paymentMethod,
      cashAccountId: dto.cashAccountId,
      discount: '0',
      paidAmount: dto.paidAmount,
      items: order.items.map((i) => ({
        productId: i.productId,
        quantity: i.quantity,
        unitPrice: i.unitPrice.toString(),
      })),
    });
  }

  private async assertProductsExist(ids: string[]): Promise<void> {
    const unique = [...new Set(ids)];
    const found = await this.prisma.product.count({
      where: { id: { in: unique }, deletedAt: null },
    });

    if (found !== unique.length) throw Errors.notFound('Mahsulot');
  }

  private buildWhere(dto: ListOrdersDto): Prisma.OrderWhereInput {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    return {
      ...(dto.status ? { status: dto.status } : {}),
      ...(dto.customerId ? { customerId: dto.customerId } : {}),
      ...(dto.overdue
        ? {
            dueDate: { lt: today },
            status: { notIn: [OrderStatus.ISSUED, OrderStatus.CANCELLED] },
          }
        : {}),
    };
  }

  private include() {
    return {
      customer: { select: { id: true, name: true, phone: true } },
      items: { include: { product: { select: { id: true, sku: true, name: true } } } },
    };
  }

  /**
   * `progress`, `debt` и `isOverdue` считает сервер.
   *
   * Дублировать эти вычисления во Flutter — гарантия расхождения цифр
   * между экранами: формулу поправят в одном месте и забудут в другом.
   */
  private toPublic(order: {
    id: string;
    orderNumber: number;
    status: OrderStatus;
    dueDate: Date | null;
    issuedAt: Date | null;
    totalAmount: Prisma.Decimal;
    prepaidAmount: Prisma.Decimal;
    note: string | null;
    createdAt: Date;
    customer: { id: string; name: string; phone: string | null } | null;
    items: {
      id: string;
      quantity: number;
      producedQuantity: number;
      unitPrice: Prisma.Decimal;
      total: Prisma.Decimal;
      product: { id: string; sku: string; name: string };
    }[];
  }) {
    const ordered = order.items.reduce((sum, i) => sum + i.quantity, 0);
    const produced = order.items.reduce((sum, i) => sum + i.producedQuantity, 0);

    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const isOpen = order.status !== OrderStatus.ISSUED && order.status !== OrderStatus.CANCELLED;
    const isOverdue = order.dueDate !== null && order.dueDate < today && isOpen;

    return {
      id: order.id,
      orderNumber: order.orderNumber,
      status: order.status,
      availableTransitions: availableTransitions(order.status),
      customer: order.customer,
      dueDate: order.dueDate ? order.dueDate.toISOString().slice(0, 10) : null,
      issuedAt: order.issuedAt,
      isOverdue,
      totalAmount: order.totalAmount.toString(),
      prepaidAmount: order.prepaidAmount.toString(),
      debt: order.totalAmount.minus(order.prepaidAmount).toString(),
      progress: {
        ordered,
        produced,
        percent: ordered === 0 ? 0 : Math.round((produced / ordered) * 100),
      },
      note: order.note,
      createdAt: order.createdAt,
      items: order.items.map((i) => ({
        id: i.id,
        product: i.product,
        quantity: i.quantity,
        producedQuantity: i.producedQuantity,
        unitPrice: i.unitPrice.toString(),
        total: i.total.toString(),
      })),
    };
  }
}
