import { z } from 'zod';

const phone = z
  .string()
  .transform((v) => v.replace(/[\s()\-]/g, ''))
  .transform((v) => {
    if (v.startsWith('+998')) return v;
    if (v.startsWith('998')) return `+${v}`;
    if (v.length === 9) return `+998${v}`;
    return v;
  })
  .refine((v) => /^\+998\d{9}$/.test(v), { message: 'validation.phone_format' });

export const createEmployeeSchema = z.object({
  fullName: z.string().trim().min(2, 'validation.full_name').max(160),
  phone: phone.optional(),
  position: z.string().trim().max(80).optional(),
  /** Если у рабочего одна специализация — бот пропустит выбор операции. */
  defaultOperationId: z.string().uuid().optional(),
  hiredAt: z.coerce.date().optional(),
});

export const updateEmployeeSchema = createEmployeeSchema.partial().extend({
  isActive: z.boolean().optional(),
});

export const listEmployeesSchema = z.object({
  search: z.string().trim().min(1).max(120).optional(),
  isActive: z
    .enum(['true', 'false'])
    .transform((v) => v === 'true')
    .optional(),
});

export const statsQuerySchema = z.object({
  dateFrom: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  dateTo: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

export type CreateEmployeeDto = z.infer<typeof createEmployeeSchema>;
export type UpdateEmployeeDto = z.infer<typeof updateEmployeeSchema>;
export type ListEmployeesDto = z.infer<typeof listEmployeesSchema>;
export type StatsQueryDto = z.infer<typeof statsQuerySchema>;
