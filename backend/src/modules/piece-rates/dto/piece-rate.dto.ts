import { z } from 'zod';

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const createPieceRateSchema = z.object({
  operationId: z.string().uuid(),
  /** null — ставка действует для всех моделей */
  productId: z.string().uuid().optional(),
  /** null — ставка действует для всех сотрудников */
  employeeId: z.string().uuid().optional(),
  rate: money,
});

export const listPieceRatesSchema = z.object({
  operationId: z.string().uuid().optional(),
  productId: z.string().uuid().optional(),
  employeeId: z.string().uuid().optional(),
});

export const resolveRateSchema = z.object({
  operationId: z.string().uuid(),
  productId: z.string().uuid().optional(),
  employeeId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type CreatePieceRateDto = z.infer<typeof createPieceRateSchema>;
export type ListPieceRatesDto = z.infer<typeof listPieceRatesSchema>;
export type ResolveRateDto = z.infer<typeof resolveRateSchema>;
