import { Module } from '@nestjs/common';
import { ReportDataService } from './report-data.service';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  controllers: [ReportsController],
  providers: [ReportsService, ReportDataService],
})
export class ReportsModule {}
