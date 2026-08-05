import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CalculateDto, CreateCalculationDto } from './dto/costing.dto';

/** Строка расхода после подстановки цен из справочника. */
interface PricedItem {
  materialId: string | null;
  name: string;
  unit: string;
  quantity: Prisma.Decimal;
  unitPrice: Prisma.Decimal;
  total: Prisma.Decimal;
}

export interface Calculation {
  materialsCost: Prisma.Decimal;
  laborCost: Prisma.Decimal;
  overheadCost: Prisma.Decimal;
  totalCost: Prisma.Decimal;
  marginPercent: Prisma.Decimal;
  recommendedPrice: Prisma.Decimal;
  profitPerUnit: Prisma.Decimal;
  items: PricedItem[];
  laborBreakdown: { operation: string; rate: string }[];
}

/**
 * Калькулятор себестоимости.
 *
 * Считает, во что обходится пара: материалы плюс работа плюс накладные, —
 * и какую цену просить при желаемой марже. До него себестоимость вбивали
 * руками, а от неё считается вся прибыль в отчётах и на дашборде.
 */
@Injectable()
export class CostingService {
  constructor(private readonly prisma: PrismaService) {}

  /** Расчёт без сохранения: владелец крутит маржу и смотрит на цену. */
  async calculate(dto: CalculateDto): Promise<Calculation> {
    const items = await this.priceItems(dto);
    const materialsCost = sum(items.map((item) => item.total));

    const labor =
      dto.laborCost === null || dto.laborCost === undefined
        ? await this.laborFromRates(dto.productId)
        : { cost: new Prisma.Decimal(dto.laborCost), breakdown: [] };

    const overheadCost = new Prisma.Decimal(dto.overheadCost);
    const totalCost = materialsCost.plus(labor.cost).plus(overheadCost);
    const marginPercent = new Prisma.Decimal(dto.marginPercent);

    // Наценка на себестоимость, а не маржа в выручке: в цехе считают
    // «плюс тридцать процентов», и цифра должна означать именно это.
    const recommendedPrice = round(totalCost.times(marginPercent.dividedBy(100).plus(1)));

    return {
      materialsCost,
      laborCost: labor.cost,
      overheadCost,
      totalCost,
      marginPercent,
      recommendedPrice,
      profitPerUnit: recommendedPrice.minus(totalCost),
      items,
      laborBreakdown: labor.breakdown,
    };
  }

  async findAll(dto: PaginationDto & { productId?: string }) {
    const where: Prisma.CostCalculationWhereInput = {
      ...(dto.productId ? { productId: dto.productId } : {}),
      ...(dto.search ? { name: { contains: dto.search, mode: 'insensitive' } } : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.costCalculation.findMany({
        where,
        include: {
          product: { select: { id: true, sku: true, name: true } },
          items: true,
        },
        orderBy: { createdAt: 'desc' },
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.costCalculation.count({ where }),
    ]);

    return paginate(items, total, dto);
  }

  async findOne(id: string) {
    const calculation = await this.prisma.costCalculation.findFirst({
      where: { id },
      include: {
        product: { select: { id: true, sku: true, name: true } },
        items: true,
      },
    });

    if (!calculation) throw Errors.notFound('Kalkulyatsiya');
    return calculation;
  }

  /** Сохранение расчёта вместе со снимком цен. */
  async create(dto: CreateCalculationDto) {
    const { companyId } = requireTenant();
    const result = await this.calculate(dto);

    return this.prisma.costCalculation.create({
      data: {
        companyId,
        productId: dto.productId ?? null,
        name: dto.name,
        materialsCost: result.materialsCost,
        laborCost: result.laborCost,
        overheadCost: result.overheadCost,
        timeMinutes: dto.timeMinutes,
        totalCost: result.totalCost,
        marginPercent: result.marginPercent,
        recommendedPrice: result.recommendedPrice,
        profitPerUnit: result.profitPerUnit,
        items: {
          create: result.items.map((item) => ({
            materialId: item.materialId,
            name: item.name,
            unit: item.unit,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            total: item.total,
          })),
        },
      },
      include: { items: true },
    });
  }

  /**
   * Записать расчёт в себестоимость модели.
   *
   * Отдельным действием, а не автоматически при сохранении: расчёт часто
   * делают «на посмотреть», а `costPrice` участвует в прибыли по каждой
   * продаже — менять её молча нельзя.
   *
   * Уже проведённые продажи не трогаются: у них своя себестоимость,
   * снятая в момент продажи. Иначе прошлая прибыль поехала бы задним числом.
   */
  async apply(id: string) {
    const calculation = await this.findOne(id);
    const productId = calculation.productId;

    if (!productId) throw Errors.calculationWithoutProduct();

    return this.prisma.$transaction(async (tx) => {
      await tx.product.update({
        where: { id: productId },
        data: { costPrice: calculation.totalCost },
      });

      // Прошлый применённый расчёт по этой модели перестаёт быть текущим:
      // флаг означает «эта цифра сейчас стоит в карточке», и двух таких
      // одновременно быть не может.
      await tx.costCalculation.updateMany({
        where: { productId, isApplied: true },
        data: { isApplied: false },
      });

      return tx.costCalculation.update({
        where: { id },
        data: { isApplied: true },
        include: { items: true },
      });
    });
  }

  async remove(id: string) {
    await this.findOne(id);
    return this.prisma.costCalculation.delete({ where: { id } });
  }

  /**
   * Подстановка цен: для материала из справочника берём текущую цену,
   * для разового — присланную. Цена справочника выигрывает всегда, иначе
   * калькулятор можно было бы посчитать по цене, которой не существует.
   */
  private async priceItems(dto: CalculateDto): Promise<PricedItem[]> {
    const ids = dto.items
      .map((item) => item.materialId)
      .filter((id): id is string => id !== undefined);

    const materials = ids.length
      ? await this.prisma.material.findMany({ where: { id: { in: ids }, deletedAt: null } })
      : [];

    const byId = new Map(materials.map((material) => [material.id, material]));

    return dto.items.map((item) => {
      const material = item.materialId ? byId.get(item.materialId) : undefined;

      if (item.materialId && !material) throw Errors.notFound('Material');

      const name = material?.name ?? item.name;
      const unit = material?.unit ?? item.unit;

      // Схема это уже гарантировала, но проверка здесь не лишняя: сервис
      // вызывается и из `create`, и падать он должен понятной ошибкой,
      // а не «name of undefined» при следующей правке схемы.
      if (!name || !unit) throw Errors.notFound('Material');

      const quantity = new Prisma.Decimal(item.quantity);
      const unitPrice = new Prisma.Decimal(material?.unitPrice ?? item.unitPrice ?? 0);

      return {
        materialId: material?.id ?? null,
        name,
        unit,
        quantity,
        unitPrice,
        total: round(quantity.times(unitPrice)),
      };
    });
  }

  /**
   * Стоимость работы из реальных расценок, по которым платится зарплата.
   *
   * Вводить её руками можно, но по умолчанию она берётся отсюда: иначе
   * калькулятор начнёт врать в тот день, когда расценки поднимут, и
   * никто об этом не вспомнит.
   *
   * Берутся расценки, действующие сегодня: у расценки есть срок, и
   * прошлогодняя не должна занижать себестоимость.
   */
  private async laborFromRates(productId?: string) {
    if (!productId) {
      return { cost: new Prisma.Decimal(0), breakdown: [] };
    }

    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const rates = await this.prisma.pieceRate.findMany({
      where: {
        productId,
        validFrom: { lte: today },
        OR: [{ validTo: null }, { validTo: { gte: today } }],
      },
      include: { operation: { select: { name: true } } },
      orderBy: { validFrom: 'desc' },
    });

    // На операцию может быть несколько расценок (общая и персональная
    // для сотрудника). В себестоимость идёт одна — самая свежая по этой
    // операции, иначе работа посчитается дважды.
    const byOperation = new Map<string, { name: string; rate: Prisma.Decimal }>();

    for (const rate of rates) {
      if (byOperation.has(rate.operationId)) continue;
      byOperation.set(rate.operationId, {
        name: rate.operation.name,
        rate: new Prisma.Decimal(rate.rate),
      });
    }

    const breakdown = [...byOperation.values()].map((entry) => ({
      operation: entry.name,
      rate: entry.rate.toString(),
    }));

    return {
      cost: sum([...byOperation.values()].map((entry) => entry.rate)),
      breakdown,
    };
  }
}

function sum(values: Prisma.Decimal[]): Prisma.Decimal {
  return values.reduce((acc, value) => acc.plus(value), new Prisma.Decimal(0));
}

/** Округление до копеек: в базе Decimal(14,2), и лишние знаки она отбросит сама. */
function round(value: Prisma.Decimal): Prisma.Decimal {
  return new Prisma.Decimal(value.toFixed(2));
}
