import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Idempotent } from '../../common/decorators/idempotent.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CancelSaleDto,
  CreateSaleDto,
  ListSalesDto,
  cancelSaleSchema,
  createSaleSchema,
  listSalesSchema,
} from './dto/sale.dto';
import { SalesService } from './sales.service';

@Controller('sales')
@Roles(UserRole.ACCOUNTANT)
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  findAll(
    @Query(new ZodValidationPipe(listSalesSchema.merge(paginationSchema)))
    query: ListSalesDto & PaginationDto,
  ) {
    return this.sales.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.sales.findOne(id);
  }

  /** Продаёт и мастер — он стоит за прилавком при отгрузке из цеха. */
  @Post()
  @Roles(UserRole.ADMIN, UserRole.ACCOUNTANT)
  @Idempotent()
  create(
    @Body(new ZodValidationPipe(createSaleSchema)) dto: CreateSaleDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.sales.create(dto, user.userId);
  }

  /** Не удаление, а сторно: возврат на склад и обратная проводка в кассе. */
  @Delete(':id')
  @Roles(UserRole.OWNER)
  cancel(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(cancelSaleSchema)) dto: CancelSaleDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.sales.cancel(id, dto.reason, user.userId);
  }
}
