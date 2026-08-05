import { Module } from '@nestjs/common';
import { CostingController } from './costing.controller';
import { CostingService } from './costing.service';

@Module({
  controllers: [CostingController],
  providers: [CostingService],
})
export class CostingModule {}
