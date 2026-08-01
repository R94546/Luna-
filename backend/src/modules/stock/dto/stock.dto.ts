import { StockMovementType } from '@prisma/client';
import { z } from 'zod';
import { paginationSchema } from '../../../common/dto/pagination.dto';

export const createMovementSchema = z.object({
  productId: z.string().uuid(),
  type: z.nativeEnum(StockMovementType),
  /**
   * Для ADJUSTMENT — фактический остаток после пересчёта (может быть 0),
   * для остальных типов — количество, всегда положительное.
   */
  quantity: z.coerce.number().int().min(0),
  note: z.string().trim().max(255).optional(),
}).refine((d) => d.type === StockMovementType.ADJUSTMENT || d.quantity > 0, {
  message: 'validation.positive',
  path: ['quantity'],
});

export const listMovementsSchema = paginationSchema.extend({
  productId: z.string().uuid().optional(),
  type: z.nativeEnum(StockMovementType).optional(),
});

export type CreateMovementDto = z.infer<typeof createMovementSchema>;
export type ListMovementsDto = z.infer<typeof listMovementsSchema>;
