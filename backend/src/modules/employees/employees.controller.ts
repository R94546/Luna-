import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateEmployeeDto,
  ListEmployeesDto,
  StatsQueryDto,
  UpdateEmployeeDto,
  createEmployeeSchema,
  listEmployeesSchema,
  statsQuerySchema,
  updateEmployeeSchema,
} from './dto/employee.dto';
import { EmployeesService } from './employees.service';

@Controller('employees')
export class EmployeesController {
  constructor(
    private readonly employees: EmployeesService,
    private readonly config: ConfigService,
  ) {}

  @Get()
  findAll(@Query(new ZodValidationPipe(listEmployeesSchema)) query: ListEmployeesDto) {
    return this.employees.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.employees.findOne(id);
  }

  @Get(':id/stats')
  stats(
    @Param('id', ParseUUIDPipe) id: string,
    @Query(new ZodValidationPipe(statsQuerySchema)) query: StatsQueryDto,
  ) {
    return this.employees.stats(id, query.dateFrom, query.dateTo);
  }

  @Post()
  @Roles(UserRole.ADMIN)
  create(@Body(new ZodValidationPipe(createEmployeeSchema)) dto: CreateEmployeeDto) {
    return this.employees.create(dto);
  }

  @Patch(':id')
  @Roles(UserRole.ADMIN)
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateEmployeeSchema)) dto: UpdateEmployeeDto,
  ) {
    return this.employees.update(id, dto);
  }

  @Post(':id/telegram-link')
  @Roles(UserRole.ADMIN)
  createLinkCode(@Param('id', ParseUUIDPipe) id: string) {
    const botUsername = this.config.get<string>('TELEGRAM_BOT_USERNAME', 'luna_workshop_bot');
    return this.employees.createLinkCode(id, botUsername);
  }

  @Delete(':id/telegram-link')
  @Roles(UserRole.ADMIN)
  unlinkTelegram(@Param('id', ParseUUIDPipe) id: string) {
    return this.employees.unlinkTelegram(id);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.employees.remove(id);
  }
}
