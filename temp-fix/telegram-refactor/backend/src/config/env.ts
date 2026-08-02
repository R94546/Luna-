import { z } from 'zod';

/**
 * Схема переменных окружения.
 * Валидируется при старте: приложение не поднимется с неверным конфигом,
 * вместо того чтобы упасть через час на первом обращении к Redis.
 */
const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  CORS_ORIGINS: z.string().default('*'),

  DATABASE_URL: z.string().url(),
  // Пустая строка допустима: очередей пока нет, Redis не нужен для запуска.
  REDIS_URL: z.union([z.string().url(), z.literal('')]).default(''),

  JWT_SECRET: z.string().min(32, 'JWT_SECRET должен быть не короче 32 символов'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(30),

  TELEGRAM_BOT_TOKEN: z.string().default(''),
  TELEGRAM_BOT_USERNAME: z.string().default('luna_workshop_bot'),
  TELEGRAM_WEBHOOK_SECRET: z.string().default(''),
  TELEGRAM_WEBHOOK_URL: z.string().default(''),
});

export type Env = z.infer<typeof envSchema>;

export function validateEnv(raw: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(raw);

  if (!parsed.success) {
    const problems = parsed.error.issues
      .map((i) => `  • ${i.path.join('.')}: ${i.message}`)
      .join('\n');
    throw new Error(`Ошибка конфигурации (.env):\n${problems}`);
  }

  // Проверка, которую легко забыть и дорого обнаружить в проде.
  if (parsed.data.NODE_ENV === 'production' && !parsed.data.TELEGRAM_WEBHOOK_URL) {
    throw new Error(
      'В production необходим TELEGRAM_WEBHOOK_URL: режим polling не годится для нескольких инстансов.',
    );
  }

  return parsed.data;
}
