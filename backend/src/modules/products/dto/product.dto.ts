import { z } from 'zod';
import { paginationSchema } from '../../../common/dto/pagination.dto';

/** Денежное поле: принимаем строку или число, храним строкой — Decimal без потерь. */
const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const createProductSchema = z.object({
  sku: z.string().trim().min(1, 'validation.required').max(48),
  name: z.string().trim().min(2, 'validation.required').max(160),
  category: z.string().trim().max(80).optional(),
  photoUrl: z.string().url().max(512).optional(),
  salePrice: money.default('0'),
  costPrice: money.default('0'),
  minStockLevel: z.coerce.number().int().min(0).default(0),
  initialStock: z.coerce.number().int().min(0).default(0),
});

export const updateProductSchema = createProductSchema
  .omit({ initialStock: true })
  .partial()
  .extend({ isActive: z.boolean().optional() });

export const listProductsSchema = paginationSchema.extend({
  isActive: z
    .enum(['true', 'false'])
    .transform((v) => v === 'true')
    .optional(),
});

export type CreateProductDto = z.infer<typeof createProductSchema>;
export type UpdateProductDto = z.infer<typeof updateProductSchema>;
export type ListProductsDto = z.infer<typeof listProductsSchema>;
