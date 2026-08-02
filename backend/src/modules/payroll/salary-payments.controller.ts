import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateSalaryPaymentDto,
  ListSalaryPaymentsDto,
  createSalaryPaymentSchema,
  listSalaryPaymentsSchema,
} from './dto/payroll.dto';
import { SalaryPaymentsService } from './salary-payments.service';

@Controller('salary-payments')
@Roles(UserRole.ACCOUNTANT)
export class SalaryPaymentsController {
  constructor(private readonly payments: SalaryPaymentsService) {}

  @Get()
  findAll(
    @Query(new ZodValidationPipe(listSalaryPaymentsSchema.merge(paginationSchema)))
    query: ListSalaryPaymentsDto & PaginationDto,
  ) {
    return this.payments.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.payments.findOne(id);
  }

  @Post()
  create(
    @Body(new ZodValidationPipe(createSalaryPaymentSchema)) dto: CreateSalaryPaymentDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.payments.create(dto, user.userId);
  }
}
