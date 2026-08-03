import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Idempotent } from '../../common/decorators/idempotent.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { PaginationDto, paginationSchema } from '../../common/dto/pagination.dto';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import {
  CreateExpenseDto,
  ListExpensesDto,
  UpdateExpenseDto,
  createExpenseSchema,
  listExpensesSchema,
  updateExpenseSchema,
} from './dto/expense.dto';
import { ExpensesService } from './expenses.service';

@Controller('expenses')
@Roles(UserRole.ACCOUNTANT)
export class ExpensesController {
  constructor(private readonly expenses: ExpensesService) {}

  @Get()
  findAll(
    @Query(new ZodValidationPipe(listExpensesSchema.merge(paginationSchema)))
    query: ListExpensesDto & PaginationDto,
  ) {
    return this.expenses.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.findOne(id);
  }

  /** Мастеру расход завести можно: он покупает фурнитуру в течение дня. */
  @Post()
  @Roles(UserRole.ADMIN, UserRole.ACCOUNTANT)
  @Idempotent()
  create(
    @Body(new ZodValidationPipe(createExpenseSchema)) dto: CreateExpenseDto,
    @CurrentUser() user: AuthUser,
  ) {
    return this.expenses.create(dto, user.userId);
  }

  @Patch(':id')
  update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodValidationPipe(updateExpenseSchema)) dto: UpdateExpenseDto,
  ) {
    return this.expenses.update(id, dto);
  }

  @Delete(':id')
  @Roles(UserRole.OWNER)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.remove(id);
  }
}
