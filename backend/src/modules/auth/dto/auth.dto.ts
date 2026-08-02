import { z } from 'zod';

/**
 * Телефон в формате Узбекистана: +998 и 9 цифр.
 * Нормализуем при вводе — пользователи пишут по-разному
 * (+998 90 123-45-67, 998901234567, 901234567), а в базе должен быть один вид.
 */
const phoneSchema = z
  .string()
  .transform((v) => v.replace(/[\s()-]/g, ''))
  .transform((v) => {
    if (v.startsWith('+998')) return v;
    if (v.startsWith('998')) return `+${v}`;
    if (v.length === 9) return `+998${v}`;
    return v;
  })
  .refine((v) => /^\+998\d{9}$/.test(v), { message: 'validation.phone_format' });

const passwordSchema = z
  .string()
  .min(6, 'validation.password_min')
  .max(72, 'validation.password_max');

export const registerSchema = z.object({
  companyName: z.string().trim().min(2, 'validation.company_name').max(160),
  fullName: z.string().trim().min(2, 'validation.full_name').max(160),
  phone: phoneSchema,
  password: passwordSchema,
});

export const loginSchema = z.object({
  phone: phoneSchema,
  password: z.string().min(1, 'validation.password_required'),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(32),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: passwordSchema,
});

export type RegisterDto = z.infer<typeof registerSchema>;
export type LoginDto = z.infer<typeof loginSchema>;
export type RefreshDto = z.infer<typeof refreshSchema>;
export type ChangePasswordDto = z.infer<typeof changePasswordSchema>;

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface JwtPayload {
  sub: string;
  companyId: string;
  role: string;
}
