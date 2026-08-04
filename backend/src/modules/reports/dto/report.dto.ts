import { z } from 'zod';

export const REPORT_TYPES = ['FINANCE', 'SALES', 'PAYROLL', 'PRODUCTION', 'STOCK'] as const;
export const REPORT_FORMATS = ['PDF', 'XLSX'] as const;

export type ReportType = (typeof REPORT_TYPES)[number];
export type ReportFormat = (typeof REPORT_FORMATS)[number];

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

export const exportReportSchema = z
  .object({
    type: z.enum(REPORT_TYPES),
    format: z.enum(REPORT_FORMATS),
    dateFrom: date,
    dateTo: date,
  })
  .refine((v) => v.dateFrom <= v.dateTo, {
    message: 'validation.date_range',
    path: ['dateTo'],
  });

export type ExportReportDto = z.infer<typeof exportReportSchema>;

export type ReportJobStatus = 'PENDING' | 'READY' | 'FAILED';

export interface ReportJob {
  jobId: string;
  companyId: string;
  status: ReportJobStatus;
  type: ReportType;
  format: ReportFormat;
  fileName: string;
  /** Путь к готовому файлу. Появляется вместе со статусом READY. */
  filePath?: string;
  /** Код ошибки для клиента — текст сообщения в лог, а не пользователю. */
  error?: string;
  createdAt: Date;
  expiresAt: Date;
}
