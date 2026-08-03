import { Module } from '@nestjs/common';
import { SalesModule } from '../sales/sales.module';
import { StockModule } from '../stock/stock.module';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [StockModule, SalesModule],
  controllers: [OrdersController],
  providers: [OrdersService],
})
export class OrdersModule {}
