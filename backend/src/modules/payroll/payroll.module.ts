import { Module } from '@nestjs/common';
import { CashModule } from '../cash/cash.module';
import { PayrollController } from './payroll.controller';
import { PayrollService } from './payroll.service';
import { SalaryPaymentsController } from './salary-payments.controller';
import { SalaryPaymentsService } from './salary-payments.service';

/**
 * Начисление и выплата держатся вместе намеренно.
 *
 * Выплата обязана пересчитать начисление в своей же транзакции, а начисление
 * без выплат — половина процесса. Разнеси их по модулям, и между ними
 * появится либо циклическая зависимость, либо третий модуль-посредник.
 */
@Module({
  imports: [CashModule],
  controllers: [PayrollController, SalaryPaymentsController],
  providers: [PayrollService, SalaryPaymentsService],
  exports: [PayrollService],
})
export class PayrollModule {}
