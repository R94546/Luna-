import { Body, Controller, Get, Post } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import { CreateCategoryDto, createCategorySchema } from './dto/expense.dto';
import { ExpensesService } from './expenses.service';

@Controller('expense-categories')
export class ExpenseCategoriesController {
  constructor(private readonly expenses: ExpensesService) {}

  /** Список нужен всем, кто заводит расход, — в том числе мастеру. */
  @Get()
  findAll() {
    return this.expenses.findAllCategories();
  }

  @Post()
  @Roles(UserRole.ACCOUNTANT)
  create(@Body(new ZodValidationPipe(createCategorySchema)) dto: CreateCategoryDto) {
    return this.expenses.createCategory(dto);
  }
}
