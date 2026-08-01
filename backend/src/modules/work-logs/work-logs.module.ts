import { Module } from '@nestjs/common';
import { PieceRatesModule } from '../piece-rates/piece-rates.module';
import { WorkLogsController } from './work-logs.controller';
import { WorkLogsService } from './work-logs.service';

@Module({
  imports: [PieceRatesModule],
  controllers: [WorkLogsController],
  providers: [WorkLogsService],
  exports: [WorkLogsService],
})
export class WorkLogsModule {}
