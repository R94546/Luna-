import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

/**
 * Период задаётся либо именем, либо парой дат.
 *
 * Обе даты вместе — иначе непонятно, чем достраивать вторую, и «с 1 августа»
 * молча превратилось бы в «по сегодня», о чём клиент не просил.
 */
const periodBase = z
  .object({
    period: z.enum(['week', 'month', 'quarter', 'year']).default('month'),
    dateFrom: isoDate.optional(),
    dateTo: isoDate.optional(),
  })
  .refine((v) => Boolean(v.dateFrom) === Boolean(v.dateTo), {
    message: 'validation.both_dates_required',
    path: ['dateTo'],
  })
  .refine((v) => !v.dateFrom || !v.dateTo || v.dateFrom <= v.dateTo, {
    message: 'validation.period_order',
    path: ['dateTo'],
  });

export const dashboardSchema = periodBase;

export const profitSchema = periodBase;

export const topProductsSchema = z
  .object({
    period: z.enum(['week', 'month', 'quarter', 'year']).default('month'),
    dateFrom: isoDate.optional(),
    dateTo: isoDate.optional(),
    limit: z.coerce.number().int().min(1).max(50).default(10),
    sort: z.enum(['revenue', 'profit', 'units']).default('revenue'),
  })
  .refine((v) => Boolean(v.dateFrom) === Boolean(v.dateTo), {
    message: 'validation.both_dates_required',
    path: ['dateTo'],
  });

export const productionSchema = z
  .object({
    period: z.enum(['week', 'month', 'quarter', 'year']).default('month'),
    dateFrom: isoDate.optional(),
    dateTo: isoDate.optional(),
    groupBy: z.enum(['day', 'employee', 'product']).default('day'),
  })
  .refine((v) => Boolean(v.dateFrom) === Boolean(v.dateTo), {
    message: 'validation.both_dates_required',
    path: ['dateTo'],
  });

export type DashboardDto = z.infer<typeof dashboardSchema>;
export type ProfitDto = z.infer<typeof profitSchema>;
export type TopProductsDto = z.infer<typeof topProductsSchema>;
export type ProductionDto = z.infer<typeof productionSchema>;
