import { z } from 'zod';

export const createOperationSchema = z.object({
  name: z.string().trim().min(2, 'validation.required').max(80),
  code: z.string().trim().max(32).optional(),
  sortOrder: z.coerce.number().int().min(0).default(0),
});

export const updateOperationSchema = createOperationSchema.partial().extend({
  isActive: z.boolean().optional(),
});

export type CreateOperationDto = z.infer<typeof createOperationSchema>;
export type UpdateOperationDto = z.infer<typeof updateOperationSchema>;
