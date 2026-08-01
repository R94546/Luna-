import { Injectable } from '@nestjs/common';
import { Prisma, StockMovementType } from '@prisma/client';
import { Errors } from '../../common/filters/app.exception';
import { PaginationDto, paginate, parseSort } from '../../common/dto/pagination.dto';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateProductDto, UpdateProductDto } from './dto/product.dto';

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(dto: PaginationDto & { isActive?: boolean }) {
    const where: Prisma.ProductWhereInput = {
      deletedAt: null,
      ...(dto.isActive === undefined ? {} : { isActive: dto.isActive }),
      ...(dto.search
        ? {
            OR: [
              { name: { contains: dto.search, mode: 'insensitive' } },
              { sku: { contains: dto.search, mode: 'insensitive' } },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.product.findMany({
        where,
        orderBy: parseSort(dto.sort, { name: 'asc' }),
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.product.count({ where }),
    ]);

    return paginate(items.map((p) => this.withStockFlag(p)), total, dto);
  }

  async findOne(id: string) {
    const product = await this.prisma.product.findFirst({ where: { id, deletedAt: null } });
    if (!product) throw Errors.notFound('Mahsulot');
    return this.withStockFlag(product);
  }

  /** Товары, которых осталось меньше минимального уровня — для уведомлений. */
  async findLowStock() {
    const items = await this.prisma.product.findMany({
      where: { deletedAt: null, isActive: true },
      orderBy: { stockQuantity: 'asc' },
    });

    // Сравнение двух колонок между собой Prisma не умеет, поэтому фильтруем
    // в приложении. Справочник моделей у цеха — десятки строк, это дешевле,
    // чем $queryRaw и потеря типизации. Для крона есть partial-индекс
    // idx_products_low_stock, туда пойдёт сырой SQL, когда понадобится.
    return items.filter((p) => p.stockQuantity <= p.minStockLevel);
  }

  /**
   * Создание товара. Если указан начальный остаток — сразу пишем движение
   * склада, иначе products.stock_quantity разойдётся с журналом и
   * триггер сверки заблокирует первую же реальную операцию.
   */
  async create(dto: CreateProductDto, userId: string) {
    const { initialStock = 0, ...data } = dto;
    const { companyId } = requireTenant();

    return this.prisma.$transaction(async (tx) => {
      const product = await tx.product.create({
        data: { ...data, companyId, stockQuantity: initialStock },
      });

      if (initialStock > 0) {
        await tx.stockMovement.create({
          data: {
            companyId: product.companyId,
            productId: product.id,
            type: StockMovementType.ADJUSTMENT,
            quantity: initialStock,
            balanceAfter: initialStock,
            note: "Boshlang'ich qoldiq",
            createdById: userId,
          },
        });
      }

      return this.withStockFlag(product);
    });
  }

  /**
   * Остаток через этот метод не меняется — только через stock-модуль.
   * Иначе появится второй путь изменения склада в обход журнала.
   */
  async update(id: string, dto: UpdateProductDto) {
    await this.findOne(id);
    return this.prisma.product.update({ where: { id }, data: dto });
  }

  async remove(id: string) {
    await this.findOne(id);

    return this.prisma.product.update({
      where: { id },
      data: { deletedAt: new Date(), isActive: false },
    });
  }

  /** Готовый флаг для интерфейса, чтобы клиент не сравнивал числа сам. */
  private withStockFlag<T extends { stockQuantity: number; minStockLevel: number }>(product: T) {
    return { ...product, isLowStock: product.stockQuantity <= product.minStockLevel };
  }
}
