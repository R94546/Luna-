import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { Observable } from 'rxjs';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { AppException } from '../filters/app.exception';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext): boolean | Promise<boolean> | Observable<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    return isPublic ? true : super.canActivate(context);
  }

  handleRequest<TUser>(err: unknown, user: TUser, info: unknown): TUser {
    if (user) return user;

    // Клиенту важно отличать «токен протух» (надо сделать refresh)
    // от «токен неверный» (надо разлогинить). Без разделения Flutter
    // будет выкидывать пользователя на логин каждые 15 минут.
    // Сверка по name, а не instanceof: не тянем jsonwebtoken в зависимости
    // ради одной проверки, и не ломаемся при дублировании его в node_modules.
    if ((info as Error | undefined)?.name === 'TokenExpiredError') {
      throw new AppException(401, 'TOKEN_EXPIRED', 'error.token_expired');
    }

    throw new AppException(401, 'UNAUTHORIZED', 'error.unauthorized');
  }
}
