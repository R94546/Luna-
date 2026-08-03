import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { TenantInterceptor } from './common/guards/tenant.guard';
import { IdempotencyInterceptor } from './common/idempotency/idempotency.interceptor';
import { IdempotencyModule } from './common/idempotency/idempotency.module';
import { validateEnv } from './config/env';
import { AnalyticsModule } from './modules/analytics/analytics.module';
import { AuthModule } from './modules/auth/auth.module';
import { CashModule } from './modules/cash/cash.module';
import { CustomersModule } from './modules/customers/customers.module';
import { EmployeesModule } from './modules/employees/employees.module';
import { ExpensesModule } from './modules/expenses/expenses.module';
import { OperationsModule } from './modules/operations/operations.module';
import { OrdersModule } from './modules/orders/orders.module';
import { SalesModule } from './modules/sales/sales.module';
import { PayrollModule } from './modules/payroll/payroll.module';
import { PieceRatesModule } from './modules/piece-rates/piece-rates.module';
import { ProductsModule } from './modules/products/products.module';
import { StockModule } from './modules/stock/stock.module';
import { TelegramModule } from './modules/telegram/telegram.module';
import { WorkLogsModule } from './modules/work-logs/work-logs.module';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: 120 }]),
    ScheduleModule.forRoot(),
    PrismaModule,
    IdempotencyModule,
    AuthModule,
    EmployeesModule,
    OperationsModule,
    ProductsModule,
    StockModule,
    PieceRatesModule,
    WorkLogsModule,
    CashModule,
    PayrollModule,
    ExpensesModule,
    CustomersModule,
    SalesModule,
    OrdersModule,
    AnalyticsModule,
    TelegramModule,
  ],
  providers: [
    { provide: APP_FILTER, useClass: AllExceptionsFilter },

    // Порядок важен: сначала throttler, затем аутентификация,
    // затем проверка роли. Guard'ы выполняются в порядке объявления.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },

    // Интерцептор ставит tenant-контекст ПОСЛЕ guard'ов, когда request.user
    // уже заполнен, и держит его на всё время обработки запроса.
    { provide: APP_INTERCEPTOR, useClass: TenantInterceptor },

    // Строго после TenantInterceptor: ключи идемпотентности хранятся
    // по компаниям, и без контекста запрос к ним не отфильтруется.
    { provide: APP_INTERCEPTOR, useClass: IdempotencyInterceptor },
  ],
})
export class AppModule {}
