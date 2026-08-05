import { z } from 'zod';
import { paginationSchema } from '../../../common/dto/pagination.dto';

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

/**
 * Строка расхода: либо ссылка на справочник, либо разовый материал.
 *
 * Разовый нужен затем, что половина мелочи в цехе покупается один раз
 * под конкретную модель, и заводить ради неё карточку в справочнике
 * никто не станет — а в себестоимость она входит.
 */
const itemSchema = z
  .object({
    materialId: z.string().uuid().optional(),
    name: z.string().trim().min(1).max(120).optional(),
    unit: z.string().trim().min(1).max(16).optional(),
    unitPrice: money.optional(),
    quantity: z.coerce.number().positive('validation.positive'),
  })
  .refine((item) => item.materialId !== undefined || item.name !== undefined, {
    message: 'validation.material_required',
    path: ['materialId'],
  })
  .refine(
    (item) =>
      item.materialId !== undefined ||
      (item.unit !== undefined && item.unitPrice !== undefined),
    { message: 'validation.material_price_required', path: ['unitPrice'] },
  );

export const calculateSchema = z.object({
  productId: z.string().uuid().optional(),
  items: z.array(itemSchema).min(1, 'validation.items_required'),
  /// null или отсутствует — сервер сложит расценки операций модели сам.
  laborCost: money.nullish(),
  overheadCost: money.default('0'),
  timeMinutes: z.coerce.number().int().min(0).default(0),
  marginPercent: z.coerce.number().min(0).max(1000).default(30),
});

export const createCalculationSchema = calculateSchema.extend({
  name: z.string().trim().min(2, 'validation.required').max(160),
});

export const listCalculationsSchema = paginationSchema.extend({
  productId: z.string().uuid().optional(),
});

export type CalculateDto = z.infer<typeof calculateSchema>;
export type CreateCalculationDto = z.infer<typeof createCalculationSchema>;
export type ListCalculationsDto = z.infer<typeof listCalculationsSchema>;
