import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v) && Number(v) > 0, {
    message: 'validation.positive',
  });

export const createExpenseSchema = z.object({
  categoryId: z.string().uuid(),
  amount: money,
  spentAt: isoDate,
  cashAccountId: z.string().uuid(),
  note: z.string().trim().max(255).optional(),
});

export const updateExpenseSchema = z
  .object({
    categoryId: z.string().uuid().optional(),
    amount: money.optional(),
    spentAt: isoDate.optional(),
    note: z.string().trim().max(255).optional(),
  })
  .refine((v) => Object.values(v).some((x) => x !== undefined), {
    message: 'validation.nothing_to_update',
  });

export const listExpensesSchema = z.object({
  categoryId: z.string().uuid().optional(),
  dateFrom: isoDate.optional(),
  dateTo: isoDate.optional(),
});

export const createCategorySchema = z.object({
  name: z.string().trim().min(2, 'validation.required').max(80),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/, 'validation.color_format').optional(),
});

export type CreateExpenseDto = z.infer<typeof createExpenseSchema>;
export type UpdateExpenseDto = z.infer<typeof updateExpenseSchema>;
export type ListExpensesDto = z.infer<typeof listExpensesSchema>;
export type CreateCategoryDto = z.infer<typeof createCategorySchema>;
