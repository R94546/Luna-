import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreatePeriodDto,
  ListPeriodsDto,
  PreviewDto,
  UpdateEntryDto,
  createPeriodSchema,
  listPeriodsSchema,
  previewSchema,
  updateEntrySchema,
} from './dto/payroll.dto';
import { PayrollService } from './payroll.service';

/**
 * Зарплата — зона владельца и бухгалтера. Мастер (ADMIN) подтверждает
 * выработку, но сумм к выплате не видит: в цехе это чувствительные данные.
 */
@Controller('payroll')
@Roles(UserRole.ACCOUNTANT)
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('periods')
  findAllPeriods(@Query(new ZodValidationPipe(listPeriodsSchema)) query: ListPeriodsDto) {
    return this.payroll.findAllPeriods(query);
  }

  // До 'periods/:id', иначе 'preview' будет разобрано как UUID.
  @Get('preview')
  preview(@Query(new ZodValidationPipe(previewSchema)) query: PreviewDto) {
    return this.payroll.preview(query);
  }

  @Get('periods/:id')
  findOnePeriod(@Param('id', ParseUUIDPipe) id: string) {
    return this.payroll.findOnePeriod(id);
  }

  @Post('periods')
  createPeriod(@Body(new ZodValidationPipe(createPeriodSchema)) dto: CreatePeriodDto) {
    return this.payroll.createPeriod(dto);
  }

  @Post('periods/:id/calculate')
  @HttpCode(200)
  calculate(@Param('id', ParseUUIDPipe) id: string) {
    return this.payroll.calculate(id);
  }

  @Post('periods/:id/close')
  @HttpCode(200)
  close(@Param('id', ParseUUIDPipe) id: string) {
    return this.payroll.close(id);
  }

  @Patch('entries/:id')
  updateEntry(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateEntrySchema)) dto: UpdateEntryDto,
  ) {
    return this.payroll.updateEntry(id, dto);
  }
}
