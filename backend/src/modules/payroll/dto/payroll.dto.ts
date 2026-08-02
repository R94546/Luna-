import { SalaryPaymentType } from '@prisma/client';
import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

/**
 * Денежная сумма приходит строкой и строкой же остаётся до Prisma.Decimal.
 *
 * Через number её пропускать нельзя: суммы в сумах доходят до сотен
 * миллионов, и float начинает терять копейки ровно там, где сходится
 * зарплатная ведомость.
 */
const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

const positiveMoney = money.refine((v) => Number(v) > 0, { message: 'validation.positive' });

export const createPeriodSchema = z
  .object({
    periodStart: isoDate,
    periodEnd: isoDate,
  })
  .refine((v) => v.periodStart <= v.periodEnd, {
    message: 'validation.period_order',
    path: ['periodEnd'],
  });

export const listPeriodsSchema = z.object({
  status: z.enum(['OPEN', 'CLOSED', 'PAID']).optional(),
});

export const updateEntrySchema = z
  .object({
    bonus: money.optional(),
    deduction: money.optional(),
  })
  .refine((v) => v.bonus !== undefined || v.deduction !== undefined, {
    message: 'validation.nothing_to_update',
  });

export const previewSchema = z
  .object({
    dateFrom: isoDate,
    dateTo: isoDate,
  })
  .refine((v) => v.dateFrom <= v.dateTo, {
    message: 'validation.period_order',
    path: ['dateTo'],
  });

export const createSalaryPaymentSchema = z.object({
  employeeId: z.string().uuid(),
  type: z.nativeEnum(SalaryPaymentType),
  amount: positiveMoney,
  paidAt: isoDate,
  cashAccountId: z.string().uuid(),
  /** Явная привязка к начислению. Без неё аванс ищет открытый период сам. */
  payrollEntryId: z.string().uuid().optional(),
  note: z.string().trim().max(255).optional(),
});

export const listSalaryPaymentsSchema = z.object({
  employeeId: z.string().uuid().optional(),
  type: z.nativeEnum(SalaryPaymentType).optional(),
  dateFrom: isoDate.optional(),
  dateTo: isoDate.optional(),
});

export type CreatePeriodDto = z.infer<typeof createPeriodSchema>;
export type ListPeriodsDto = z.infer<typeof listPeriodsSchema>;
export type UpdateEntryDto = z.infer<typeof updateEntrySchema>;
export type PreviewDto = z.infer<typeof previewSchema>;
export type CreateSalaryPaymentDto = z.infer<typeof createSalaryPaymentSchema>;
export type ListSalaryPaymentsDto = z.infer<typeof listSalaryPaymentsSchema>;
