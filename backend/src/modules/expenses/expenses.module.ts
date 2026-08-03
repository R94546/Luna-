import { Module } from '@nestjs/common';
import { CashModule } from '../cash/cash.module';
import { ExpenseCategoriesController } from './expense-categories.controller';
import { ExpensesController } from './expenses.controller';
import { ExpensesService } from './expenses.service';

@Module({
  imports: [CashModule],
  controllers: [ExpensesController, ExpenseCategoriesController],
  providers: [ExpensesService],
})
export class ExpensesModule {}
