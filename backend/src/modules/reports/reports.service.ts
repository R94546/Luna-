import { randomUUID } from 'node:crypto';
import { mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Errors } from '../../common/filters/app.exception';
import { TenantContext, requireTenant, runWithTenant } from '../../prisma/tenant-context';
import { buildPdf } from './builders/pdf.builder';
import { buildXlsx } from './builders/xlsx.builder';
import { ExportReportDto, ReportJob } from './dto/report.dto';
import { ReportDataService } from './report-data.service';

/** Сколько живёт готовый файл. Дальше — удаляется вместе с записью. */
const TTL_MS = 30 * 60 * 1000;

/**
 * Экспорт отчётов.
 *
 * Генерация асинхронная: ведомость за год — это секунды работы, и на плохой
 * связи HTTP-таймаут наступит раньше, чем ответ. Клиент получает `jobId`
 * и опрашивает статус.
 *
 * Очередь — своя, в памяти процесса, а не BullMQ: задача живёт полминуты,
 * переживать перезапуск ей незачем (проще нажать «Экспорт» ещё раз), а
 * Redis-воркер добавил бы отдельный процесс к развёртыванию цеха, где
 * бэкенд и так один. Когда инстансов станет несколько, замена — здесь,
 * контракт наружу не поменяется.
 */
@Injectable()
export class ReportsService implements OnModuleInit {
  private readonly logger = new Logger(ReportsService.name);
  private readonly jobs = new Map<string, ReportJob>();
  private readonly dir = join(tmpdir(), 'luna-reports');

  constructor(private readonly data: ReportDataService) {}

  async onModuleInit(): Promise<void> {
    await mkdir(this.dir, { recursive: true });
  }

  /** Ставит отчёт в очередь и сразу возвращает управление. */
  enqueue(dto: ExportReportDto): ReportJob {
    const tenant = requireTenant();
    const jobId = randomUUID();
    const extension = dto.format === 'XLSX' ? 'xlsx' : 'pdf';

    const job: ReportJob = {
      jobId,
      companyId: tenant.companyId,
      status: 'PENDING',
      type: dto.type,
      format: dto.format,
      fileName: `${dto.type.toLowerCase()}-${dto.dateFrom}_${dto.dateTo}.${extension}`,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + TTL_MS),
    };

    this.jobs.set(jobId, job);

    // Контекст арендатора живёт в AsyncLocalStorage запроса и до фоновой
    // задачи не долетит — переносим его явно. Без этого выборки отчёта
    // ушли бы в базу без фильтра по компании.
    void this.generate(job, dto, { companyId: tenant.companyId, userId: tenant.userId });

    return job;
  }

  /** Статус задачи. Чужие компании не видят даже факта существования. */
  find(jobId: string): ReportJob {
    const tenant = requireTenant();
    const job = this.jobs.get(jobId);

    if (!job || job.companyId !== tenant.companyId) throw Errors.notFound('Hisobot');

    return job;
  }

  /** Готовый файл для отдачи клиенту. */
  file(jobId: string): { path: string; fileName: string; format: string } {
    const job = this.find(jobId);

    if (job.status !== 'READY' || !job.filePath) throw Errors.notFound('Hisobot');

    return { path: job.filePath, fileName: job.fileName, format: job.format };
  }

  private async generate(
    job: ReportJob,
    dto: ExportReportDto,
    tenant: TenantContext,
  ): Promise<void> {
    const filePath = join(this.dir, `${job.jobId}-${job.fileName}`);

    try {
      const document = await runWithTenant(tenant, () =>
        this.data.build(dto.type, dto.dateFrom, dto.dateTo),
      );

      if (dto.format === 'XLSX') {
        await buildXlsx(document, filePath);
      } else {
        await buildPdf(document, filePath);
      }

      job.filePath = filePath;
      job.status = 'READY';
    } catch (error) {
      // Клиенту хватает статуса: причина — наша проблема, а не его.
      job.status = 'FAILED';
      job.error = 'REPORT_FAILED';

      this.logger.error(
        `Не удалось собрать отчёт ${dto.type}/${dto.format}: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Уборка просроченных отчётов.
   *
   * Без неё папка растёт до конца диска: отчёт за год — это мегабайты,
   * а нажимают «Экспорт» по нескольку раз в день.
   */
  @Cron(CronExpression.EVERY_10_MINUTES)
  async cleanup(): Promise<void> {
    const now = Date.now();

    for (const [jobId, job] of this.jobs) {
      if (job.expiresAt.getTime() > now) continue;

      this.jobs.delete(jobId);
      if (!job.filePath) continue;

      await rm(job.filePath, { force: true }).catch((error: Error) =>
        this.logger.warn(`Не удалось удалить ${job.filePath}: ${error.message}`),
      );
    }
  }
}
