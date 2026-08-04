import { z } from 'zod';

export const listNotificationsSchema = z.object({
  unreadOnly: z
    .enum(['true', 'false'])
    .transform((v) => v === 'true')
    .optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

export const pushTokenSchema = z.object({
  token: z.string().trim().min(10).max(255),
  platform: z.enum(['android', 'ios', 'web']),
});

export type ListNotificationsDto = z.infer<typeof listNotificationsSchema>;
export type PushTokenDto = z.infer<typeof pushTokenSchema>;
