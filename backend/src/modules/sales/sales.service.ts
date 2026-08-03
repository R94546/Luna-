import { Injectable } from '@nestjs/common';
import {
  CashCategory,
  CashDirection,
  PaymentMethod,
  Prisma,
  StockMovementType,
} from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { AppException, Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CashService } from '../cash/cash.service';
import { StockService } from '../stock/stock.service';
import { CreateSaleDto, ListSalesDto, SaleItemDto } from './dto/sale.dto';

const ZERO = new Prisma.Decimal(0);
const REF_TYPE = 'sale';

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly stock: StockService,
    private readonly cash: CashService,
  ) {}

  async findAll(dto: ListSalesDto & PaginationDto) {
    const where = this.buildWhere(dto);

    const [items, total, totals] = await Promise.all([
      this.prisma.sale.findMany({
        where,
        include: this.include(),
        orderBy: { soldAt: 'desc' },
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.sale.count({ where }),
      this.prisma.sale.aggregate({
        where,
        _sum: { totalAmount: true, totalCost: true, paidAmount: true },
      }),
    ]);

    const revenue = totals._sum.totalAmount ?? ZERO;
    const cost = totals._sum.totalCost ?? ZERO;
    const paid = totals._sum.paidAmount ?? ZERO;

    return {
      ...paginate(items.map((s) => this.toPublic(s)), total, dto),
      summary: {
        revenue: revenue.toString(),
        cost: cost.toString(),
        grossProfit: revenue.minus(cost).toString(),
        debt: revenue.minus(paid).toString(),
      },
    };
  }

  async findOne(id: string) {
    const sale = await this.prisma.sale.findFirst({ where: { id }, include: this.include() });
    if (!sale) throw Errors.notFound('Savdo');
    return this.toPublic(sale);
  }

  /**
   * Оформление продажи.
   *
   * Одной транзакцией: остаток проверяется и списывается, себестоимость
   * фиксируется, деньги приходуются в кассу, номер продажи инкрементится.
   * Разорви любое звено — и склад разойдётся с продажами либо касса
   * с выручкой, причём обнаружится это только при инвентаризации.
   *
   * Себестоимость копируется в позицию, а не берётся ссылкой на товар:
   * прибыль прошлого месяца не должна меняться от того, что сегодня
   * пересчитали калькулятор.
   */
  async create(dto: CreateSaleDto, userId?: string) {
    const prepared = await this.prepare(dto);

    const saleId = await this.prisma.$transaction((tx) =>
      this.createWithin(tx, prepared, userId),
    );

    return this.findOne(saleId);
  }

  /**
   * Проверки и расчёты до транзакции.
   *
   * Читать справочники внутри транзакции незачем — они не меняются от неё,
   * а транзакция держала бы соединение дольше нужного. Внутри остаётся
   * только то, что обязано быть атомарным: списание, деньги, номер.
   */
  private async prepare(dto: CreateSaleDto) {
    const { companyId } = requireTenant();

    const products = await this.loadProducts(dto.items);
    const account = await this.resolveAccount(dto);

    const priced = dto.items.map((item) => {
      const product = products.get(item.productId);
      if (!product) throw Errors.notFound('Mahsulot');

      const unitPrice = new Prisma.Decimal(item.unitPrice);

      return {
        productId: item.productId,
        quantity: item.quantity,
        unitPrice,
        costPriceSnapshot: product.costPrice,
        total: unitPrice.mul(item.quantity),
      };
    });

    const gross = priced.reduce((sum, i) => sum.plus(i.total), ZERO);
    const discount = new Prisma.Decimal(dto.discount);

    if (discount.gt(gross)) {
      throw new AppException(422, 'DISCOUNT_TOO_LARGE', 'error.discount_too_large');
    }

    const totalAmount = gross.minus(discount);
    const totalCost = priced.reduce(
      (sum, i) => sum.plus(i.costPriceSnapshot.mul(i.quantity)),
      ZERO,
    );

    // В долг по умолчанию не платят ничего, при остальных способах —
    // всю сумму: кассир пробивает чек целиком, частичная оплата это
    // отдельный осознанный ввод.
    const paidAmount =
      dto.paidAmount !== undefined
        ? new Prisma.Decimal(dto.paidAmount)
        : dto.paymentMethod === PaymentMethod.DEBT
          ? ZERO
          : totalAmount;

    if (paidAmount.gt(totalAmount)) {
      throw new AppException(422, 'PAID_EXCEEDS_TOTAL', 'error.paid_exceeds_total');
    }

    const soldAt = dto.soldAt ? new Date(dto.soldAt) : new Date();

    return {
      companyId,
      dto,
      priced,
      discount,
      totalAmount,
      totalCost,
      paidAmount,
      soldAt,
      accountId: account?.id ?? null,
      /** Заказ уже списал товар движением ORDER_OUT — второй раз не списываем. */
      skipStock: false,
    };
  }

  /**
   * Запись продажи внутри переданной транзакции.
   *
   * Отдельным методом, потому что выдача заказа обязана пометить заказ
   * выданным и оформить продажу атомарно: продажа без заказа или заказ
   * без продажи — расхождение, которое всплывёт при сверке кассы.
   */
  async createWithin(
    tx: Prisma.TransactionClient,
    prepared: Awaited<ReturnType<SalesService['prepare']>>,
    userId?: string,
  ): Promise<string> {
    const { companyId, dto, priced, paidAmount, soldAt } = prepared;

    const saleNumber = await this.prisma.nextNumber(tx, companyId, 'sale');

    const sale = await tx.sale.create({
      data: {
        companyId,
        saleNumber,
        customerId: dto.customerId,
        orderId: dto.orderId,
        totalAmount: prepared.totalAmount,
        discount: prepared.discount,
        paidAmount,
        totalCost: prepared.totalCost,
        paymentMethod: dto.paymentMethod,
        soldAt,
        note: dto.note,
        createdById: userId,
        items: { create: priced },
      },
    });

    if (!prepared.skipStock) {
      for (const item of priced) {
        await this.stock.applyMovement(tx, {
          companyId,
          productId: item.productId,
          type: StockMovementType.SALE_OUT,
          quantity: item.quantity,
          refType: REF_TYPE,
          refId: sale.id,
          userId,
        });
      }
    }

    // Долг деньги в кассу не приносит — движения быть не должно,
    // иначе сводка покажет выручку, которой ещё нет.
    if (prepared.accountId && paidAmount.gt(0)) {
      await this.cash.recordMovement(tx, {
        accountId: prepared.accountId,
        direction: CashDirection.IN,
        category: CashCategory.SALE,
        amount: paidAmount,
        occurredAt: soldAt,
        refType: REF_TYPE,
        refId: sale.id,
        saleId: sale.id,
        note: `Savdo №${saleNumber}`,
        userId,
      });
    }

    return sale.id;
  }

  /** Подготовка продажи по уже списанному заказу — склад трогать не нужно. */
  async prepareForIssuedOrder(dto: CreateSaleDto) {
    return { ...(await this.prepare(dto)), skipStock: true };
  }

  /**
   * Сторно.
   *
   * Продажа не удаляется: она документ перед покупателем, и её история
   * переписываться не должна. Товар возвращается на склад отдельным
   * движением, деньги — обратной проводкой в кассе, а на самой продаже
   * появляется отметка, после которой она перестаёт считаться выручкой.
   *
   * Повторное сторно запрещено — иначе товар вернулся бы на склад дважды.
   */
  async cancel(id: string, reason?: string, userId?: string) {
    const sale = await this.prisma.sale.findFirst({
      where: { id },
      include: { items: true, cashTx: true },
    });

    if (!sale) throw Errors.notFound('Savdo');

    if (sale.cancelledAt) {
      throw new AppException(422, 'SALE_ALREADY_CANCELLED', 'error.sale_already_cancelled');
    }

    await this.prisma.$transaction(async (tx) => {
      for (const item of sale.items) {
        await this.stock.applyMovement(tx, {
          companyId: sale.companyId,
          productId: item.productId,
          type: StockMovementType.RETURN_IN,
          quantity: item.quantity,
          refType: REF_TYPE,
          refId: sale.id,
          userId,
        });
      }

      // Обратная проводка, а не удаление прежней: журнал кассы — история,
      // и «денег не было» задним числом в нём появиться не может.
      for (const transaction of sale.cashTx) {
        await this.cash.recordMovement(tx, {
          accountId: transaction.accountId,
          direction:
            transaction.direction === CashDirection.IN ? CashDirection.OUT : CashDirection.IN,
          category: CashCategory.SALE,
          amount: transaction.amount,
          occurredAt: new Date(),
          refType: REF_TYPE,
          refId: sale.id,
          saleId: sale.id,
          note: `Savdo №${sale.saleNumber} bekor qilindi`,
          userId,
        });
      }

      await tx.sale.update({
        where: { id },
        data: { cancelledAt: new Date(), cancelledById: userId, cancelReason: reason },
      });
    });

    return this.findOne(id);
  }

  // ── Внутреннее ───────────────────────────────────────────────────────────

  private async loadProducts(items: SaleItemDto[]) {
    const ids = [...new Set(items.map((i) => i.productId))];

    const products = await this.prisma.product.findMany({
      where: { id: { in: ids }, deletedAt: null },
      select: { id: true, name: true, costPrice: true },
    });

    if (products.length !== ids.length) throw Errors.notFound('Mahsulot');

    return new Map(products.map((p) => [p.id, p]));
  }

  private async resolveAccount(dto: CreateSaleDto) {
    if (dto.paymentMethod === PaymentMethod.DEBT || !dto.cashAccountId) return null;

    const account = await this.prisma.cashAccount.findFirst({
      where: { id: dto.cashAccountId, isActive: true },
    });

    if (!account) throw Errors.notFound('Kassa');
    return account;
  }

  private buildWhere(dto: ListSalesDto): Prisma.SaleWhereInput {
    return {
      ...(dto.includeCancelled ? {} : { cancelledAt: null }),
      ...(dto.customerId ? { customerId: dto.customerId } : {}),
      ...(dto.paymentMethod ? { paymentMethod: dto.paymentMethod } : {}),
      ...(dto.dateFrom || dto.dateTo
        ? {
            soldAt: {
              ...(dto.dateFrom ? { gte: new Date(dto.dateFrom) } : {}),
              ...(dto.dateTo ? { lte: new Date(`${dto.dateTo}T23:59:59.999Z`) } : {}),
            },
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
   * Прибыль отдаётся вместе с продажей — владелец хочет видеть, сколько
   * заработал на ней, а не считать в уме разницу двух других полей.
   */
  private toPublic(sale: {
    id: string;
    saleNumber: number;
    totalAmount: Prisma.Decimal;
    totalCost: Prisma.Decimal;
    paidAmount: Prisma.Decimal;
    discount: Prisma.Decimal;
    paymentMethod: PaymentMethod;
    soldAt: Date;
    cancelledAt: Date | null;
    cancelReason: string | null;
    note: string | null;
    customer: { id: string; name: string; phone: string | null } | null;
    items: {
      id: string;
      quantity: number;
      unitPrice: Prisma.Decimal;
      costPriceSnapshot: Prisma.Decimal;
      total: Prisma.Decimal;
      product: { id: string; sku: string; name: string };
    }[];
  }) {
    return {
      id: sale.id,
      saleNumber: sale.saleNumber,
      customer: sale.customer,
      paymentMethod: sale.paymentMethod,
      soldAt: sale.soldAt,
      discount: sale.discount.toString(),
      totalAmount: sale.totalAmount.toString(),
      totalCost: sale.totalCost.toString(),
      grossProfit: sale.totalAmount.minus(sale.totalCost).toString(),
      paidAmount: sale.paidAmount.toString(),
      debt: sale.totalAmount.minus(sale.paidAmount).toString(),
      isCancelled: sale.cancelledAt !== null,
      cancelledAt: sale.cancelledAt,
      cancelReason: sale.cancelReason,
      note: sale.note,
      items: sale.items.map((i) => ({
        id: i.id,
        product: i.product,
        quantity: i.quantity,
        unitPrice: i.unitPrice.toString(),
        costPriceSnapshot: i.costPriceSnapshot.toString(),
        total: i.total.toString(),
      })),
    };
  }
}
