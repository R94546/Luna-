import { Module } from '@nestjs/common';
import { WorkLogsModule } from '../work-logs/work-logs.module';
import { ReportHandler } from './handlers/report.handler';
import { StartHandler } from './handlers/start.handler';
import { SummaryHandler } from './handlers/summary.handler';
import { TelegramController } from './telegram.controller';
import { TelegramSessionService } from './telegram-session.service';
import { TelegramService } from './telegram.service';

@Module({
  imports: [WorkLogsModule],
  controllers: [TelegramController],
  providers: [
    TelegramService,
    TelegramSessionService,
    StartHandler,
    ReportHandler,
    SummaryHandler,
  ],
  exports: [TelegramService],
})
export class TelegramModule {}
