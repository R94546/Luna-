import { ExecutionContext, createParamDecorator } from '@nestjs/common';
import { UserRole } from '@prisma/client';

export interface AuthUser {
  userId: string;
  companyId: string;
  role: UserRole;
}

/**
 * Достаёт авторизованного пользователя из запроса.
 * @example findAll(@CurrentUser() user: AuthUser)
 */
export const CurrentUser = createParamDecorator(
  (data: keyof AuthUser | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest<{ user: AuthUser }>();
    return data ? request.user?.[data] : request.user;
  },
);
