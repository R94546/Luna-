import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/** Отключает JwtAuthGuard для эндпоинта (логин, регистрация, вебхук Telegram). */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
