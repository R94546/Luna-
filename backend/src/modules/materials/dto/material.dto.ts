import { z } from 'zod';
import { paginationSchema } from '../../../common/dto/pagination.dto';

/** Денежное поле: принимаем строку или число, храним строкой — Decimal без потерь. */
const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const createMaterialSchema = z.object({
  name: z.string().trim().min(2, 'validation.required').max(120),
  // Единица — свободная строка: цех меряет кожу в дм², подошву в парах,
  // клей в килограммах, и загонять это в перечисление значит однажды
  // не суметь завести материал.
  unit: z.string().trim().min(1, 'validation.required').max(16),
  unitPrice: money,
});

export const updateMaterialSchema = createMaterialSchema.partial();

export const listMaterialsSchema = paginationSchema;

export type CreateMaterialDto = z.infer<typeof createMaterialSchema>;
export type UpdateMaterialDto = z.infer<typeof updateMaterialSchema>;
export type ListMaterialsDto = z.infer<typeof listMaterialsSchema>;
