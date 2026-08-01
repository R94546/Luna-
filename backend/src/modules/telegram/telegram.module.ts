import { Module } from '@nestjs/common';
import { PieceRatesModule } from '../piece-rates/piece-rates.module';
import { WorkLogsModule } from '../work-logs/work-logs.module';
import { TelegramController } from './telegram.controller';
import { TelegramService } from './telegram.service';

@Module({
  imports: [WorkLogsModule, PieceRatesModule],
  controllers: [TelegramController],
  providers: [TelegramService],
  exports: [TelegramService],
})
export class TelegramModule {}
