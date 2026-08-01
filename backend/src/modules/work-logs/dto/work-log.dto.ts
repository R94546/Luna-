import { WorkLogStatus } from '@prisma/client';
import { z } from 'zod';
import { paginationSchema } from '../../../common/dto/pagination.dto';

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const createWorkLogSchema = z.object({
  employeeId: z.string().uuid(),
  productId: z.string().uuid(),
  operationId: z.string().uuid(),
  quantity: z.coerce.number().int().positive('validation.positive'),
  workDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  /** Не указана — резолвится из расценок автоматически. */
  rate: money.optional(),
  note: z.string().trim().max(255).optional(),
});

export const listWorkLogsSchema = paginationSchema.extend({
  status: z.nativeEnum(WorkLogStatus).optional(),
  employeeId: z.string().uuid().optional(),
  productId: z.string().uuid().optional(),
  dateFrom: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export const rejectSchema = z.object({
  reason: z.string().trim().max(255).optional(),
});

export const bulkApproveSchema = z.object({
  ids: z.array(z.string().uuid()).min(1).max(200),
});

export type CreateWorkLogDto = z.infer<typeof createWorkLogSchema>;
export type ListWorkLogsDto = z.infer<typeof listWorkLogsSchema>;
export type RejectDto = z.infer<typeof rejectSchema>;
export type BulkApproveDto = z.infer<typeof bulkApproveSchema>;
