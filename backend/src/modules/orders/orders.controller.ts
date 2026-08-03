import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  ChangeStatusDto,
  CreateOrderDto,
  ListOrdersDto,
  UpdateOrderDto,
  UpdateProgressDto,
  changeStatusSchema,
  createOrderSchema,
  listOrdersSchema,
  updateOrderSchema,
  updateProgressSchema,
} from './dto/order.dto';
import { OrdersService } from './orders.service';

@Controller('orders')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Get()
  findAll(
    @Query(new ZodValidationPipe(listOrdersSchema.merge(paginationSchema)))
    query: ListOrdersDto & PaginationDto,
  ) {
    return this.orders.findAll(query);
  }

  // До ':id', иначе "overdue" будет разобрано как UUID.
  @Get('overdue')
  @Roles(UserRole.ADMIN, UserRole.ACCOUNTANT)
  findOverdue(@Query(new ZodValidationPipe(paginationSchema)) query: PaginationDto) {
    return this.orders.findOverdue(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.orders.findOne(id);
  }

  @Post()
  @Roles(UserRole.ADMIN)
  create(
    @Body(new ZodValidationPipe(createOrderSchema)) dto: CreateOrderDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.orders.create(dto, user.userId);
  }

  @Patch(':id')
  @Roles(UserRole.ADMIN)
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateOrderSchema)) dto: UpdateOrderDto,
  ) {
    return this.orders.update(id, dto);
  }

  @Patch(':id/progress')
  @Roles(UserRole.ADMIN)
  updateProgress(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateProgressSchema)) dto: UpdateProgressDto,
  ) {
    return this.orders.updateProgress(id, dto);
  }

  @Post(':id/status')
  @Roles(UserRole.ADMIN)
  @HttpCode(200)
  changeStatus(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(changeStatusSchema)) dto: ChangeStatusDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.orders.changeStatus(id, dto, user.userId);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.orders.remove(id);
  }
}
