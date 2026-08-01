import { Injectable } from '@nestjs/common';
import { Errors } from '../../common/filters/app.exception';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';
import { CreateOperationDto, UpdateOperationDto } from './dto/operation.dto';

/**
 * Операции производственного цикла: бичиш, тикиш, қолипга тортиш, қадоқлаш.
 *
 * Справочник маленький (у цеха их 4–8), поэтому пагинации нет: список
 * всегда отдаётся целиком — так его проще держать в состоянии клиента
 * и показывать в выпадающих списках без дозагрузки.
 */
@Injectable()
export class OperationsService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(includeInactive = false) {
    return this.prisma.operation.findMany({
      where: {
        deletedAt: null,
        ...(includeInactive ? {} : { isActive: true }),
      },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  async findOne(id: string) {
    const operation = await this.prisma.operation.findFirst({
      where: { id, deletedAt: null },
    });

    if (!operation) throw Errors.notFound('Operatsiya');
    return operation;
  }

  /**
   * companyId указывается явно, хотя middleware проставил бы его сам:
   * типы Prisma требуют это поле, а молчаливый каст к `any` убрал бы
   * проверку остальных полей заодно. Middleware при этом остаётся
   * страховкой — он перезапишет значение своим в любом случае.
   */
  create(dto: CreateOperationDto) {
    return this.prisma.operation.create({
      data: { ...dto, companyId: requireTenant().companyId },
    });
  }

  async update(id: string, dto: UpdateOperationDto) {
    await this.findOne(id);
    return this.prisma.operation.update({ where: { id }, data: dto });
  }

  /**
   * Мягкое удаление. Физически удалить нельзя: на операцию ссылаются
   * work_logs, а история выработки — основание для уже выплаченной зарплаты.
   */
  async remove(id: string) {
    await this.findOne(id);

    return this.prisma.operation.update({
      where: { id },
      data: { deletedAt: new Date(), isActive: false },
    });
  }
}
