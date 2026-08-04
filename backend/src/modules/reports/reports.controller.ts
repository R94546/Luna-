import { createReadStream } from 'node:fs';
import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  StreamableFile,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import type { Response } from 'express';
import { Roles } from '../../common/decorators/roles.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import { ExportReportDto, ReportJob, exportReportSchema } from './dto/report.dto';
import { ReportsService } from './reports.service';

const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

@Controller('reports')
@Roles(UserRole.ACCOUNTANT)
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  /** 202: файл ещё не готов, клиент опрашивает статус по jobId. */
  @Post('export')
  @HttpCode(202)
  export(@Body(new ZodValidationPipe(exportReportSchema)) dto: ExportReportDto) {
    return toResponse(this.reports.enqueue(dto));
  }

  @Get(':jobId')
  status(@Param('jobId', ParseUUIDPipe) jobId: string) {
    return toResponse(this.reports.find(jobId));
  }

  /**
   * Отдача файла.
   *
   * Ссылка ведёт на нас, а не на внешнее хранилище с подписанным токеном:
   * файл лежит на том же сервере, и обычной авторизации по заголовку
   * достаточно. Токен в URL пришлось бы прятать от логов и истории браузера.
   */
  @Get(':jobId/download')
  download(
    @Param('jobId', ParseUUIDPipe) jobId: string,
    @Res({ passthrough: true }) response: Response,
  ): StreamableFile {
    const file = this.reports.file(jobId);

    response.set({
      'Content-Type': file.format === 'XLSX' ? XLSX_MIME : 'application/pdf',
      // filename* с UTF-8: в имени отчёта нет кириллицы, но встроенный
      // в браузер загрузчик всё равно требует явной кодировки.
      'Content-Disposition': `attachment; filename="${file.fileName}"`,
    });

    return new StreamableFile(createReadStream(file.path));
  }
}

function toResponse(job: ReportJob) {
  return {
    jobId: job.jobId,
    status: job.status,
    type: job.type,
    format: job.format,
    fileName: job.fileName,
    url: job.status === 'READY' ? `/reports/${job.jobId}/download` : undefined,
    error: job.error,
    expiresAt: job.expiresAt,
  };
}
