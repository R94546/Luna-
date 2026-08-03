import { z } from 'zod';

/** Телефон клиента, в отличие от телефона входа, может быть любым. */
const phone = z
  .string()
  .trim()
  .transform((v) => v.replace(/[\s()-]/g, ''))
  .refine((v) => /^\+?\d{7,15}$/.test(v), { message: 'validation.phone_format' });

export const createCustomerSchema = z.object({
  name: z.string().trim().min(2, 'validation.required').max(160),
  phone: phone.optional(),
  note: z.string().trim().max(255).optional(),
});

export const updateCustomerSchema = createCustomerSchema.partial().refine(
  (v) => Object.values(v).some((x) => x !== undefined),
  { message: 'validation.nothing_to_update' },
);

export type CreateCustomerDto = z.infer<typeof createCustomerSchema>;
export type UpdateCustomerDto = z.infer<typeof updateCustomerSchema>;
