import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PaginationDto, paginate, parseSort } from '../../common/dto/pagination.dto';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateMaterialDto, UpdateMaterialDto } from './dto/material.dto';

/**
 * Справочник материалов: кожа, подошва, нитки, клей.
 *
 * Нужен калькулятору себестоимости — цены здесь одни на весь цех, и
 * поднявшаяся кожа должна отражаться в расчётах сама, без правки каждой
 * калькуляции руками.
 */
@Injectable()
export class MaterialsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(dto: PaginationDto) {
    const where: Prisma.MaterialWhereInput = {
      deletedAt: null,
      ...(dto.search ? { name: { contains: dto.search, mode: 'insensitive' } } : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.material.findMany({
        where,
        orderBy: parseSort(dto.sort, { name: 'asc' }),
        skip: (dto.page - 1) * dto.limit,
        take: dto.limit,
      }),
      this.prisma.material.count({ where }),
    ]);

    return paginate(items, total, dto);
  }

  async findOne(id: string) {
    const material = await this.prisma.material.findFirst({ where: { id, deletedAt: null } });
    if (!material) throw Errors.notFound('Material');
    return material;
  }

  create(dto: CreateMaterialDto) {
    const { companyId } = requireTenant();
    return this.prisma.material.create({ data: { ...dto, companyId } });
  }

  async update(id: string, dto: UpdateMaterialDto) {
    await this.findOne(id);
    return this.prisma.material.update({ where: { id }, data: dto });
  }

  /**
   * Мягкое удаление. Материал упомянут в сохранённых калькуляциях, и
   * стереть его насовсем значит оставить расчёты с дырой — хотя цена
   * и название в них лежат снимком и продолжат показываться.
   */
  async remove(id: string) {
    await this.findOne(id);
    return this.prisma.material.update({ where: { id }, data: { deletedAt: new Date() } });
  }
}
