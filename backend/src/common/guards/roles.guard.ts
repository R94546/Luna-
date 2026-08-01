import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { AuthUser } from '../decorators/current-user.decorator';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { Errors } from '../filters/app.exception';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!required?.length) return true;

    const { user } = context.switchToHttp().getRequest<{ user?: AuthUser }>();
    if (!user) return false;

    // Владелец видит и делает всё внутри своей компании — перечислять его
    // в каждом @Roles() значит рано или поздно где-то забыть.
    if (user.role === UserRole.OWNER || user.role === UserRole.SUPERADMIN) return true;

    if (!required.includes(user.role)) throw Errors.forbiddenRole();

    return true;
  }
}
