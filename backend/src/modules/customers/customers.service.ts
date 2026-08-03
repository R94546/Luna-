import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PaginationDto, paginate } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateCustomerDto, UpdateCustomerDto } from './dto/customer.dto';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(dto: PaginationDto) {
    const where: Prisma.CustomerWhereInput = {
      deletedAt: null,
      ...(dto.search
        ? {
            OR: [
              { name: { contains: dto.search, mode: 'insensitive' } },
              { phone: { contains: dto.search } },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.customer.findMany({
        where,
        orderBy: { name: 'asc' },
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.customer.count({ where }),
    ]);

    return paginate(items, total, dto);
  }

  /**
   * Карточка с долгом.
   *
   * Долг считается здесь, а не в приложении: он складывается из неоплаченных
   * продаж и предоплат по заказам, и посчитанный на клиенте разъедется
   * с тем, что видно в списке продаж.
   */
  async findOne(id: string) {
    const customer = await this.prisma.customer.findFirst({
      where: { id, deletedAt: null },
    });

    if (!customer) throw Errors.notFound('Mijoz');

    const [sales, orders] = await Promise.all([
      this.prisma.sale.aggregate({
        where: { customerId: id, cancelledAt: null },
        _sum: { totalAmount: true, paidAmount: true },
        _count: true,
      }),
      this.prisma.order.count({
        where: { customerId: id, status: { notIn: ['ISSUED', 'CANCELLED'] } },
      }),
    ]);

    const total = sales._sum.totalAmount ?? new Prisma.Decimal(0);
    const paid = sales._sum.paidAmount ?? new Prisma.Decimal(0);

    return {
      ...customer,
      salesCount: sales._count,
      totalAmount: total.toString(),
      debt: total.minus(paid).toString(),
      activeOrders: orders,
    };
  }

  create(dto: CreateCustomerDto) {
    return this.prisma.customer.create({
      data: { companyId: requireTenant().companyId, ...dto },
    });
  }

  async update(id: string, dto: UpdateCustomerDto) {
    const customer = await this.prisma.customer.findFirst({
      where: { id, deletedAt: null },
    });
    if (!customer) throw Errors.notFound('Mijoz');

    return this.prisma.customer.update({ where: { id }, data: dto });
  }

  /**
   * Архивирование, а не удаление: на клиента ссылаются продажи и заказы,
   * и вычеркнуть его значит потерять, кому продавали.
   */
  async remove(id: string) {
    const customer = await this.prisma.customer.findFirst({
      where: { id, deletedAt: null },
    });
    if (!customer) throw Errors.notFound('Mijoz');

    return this.prisma.customer.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
  }
}
