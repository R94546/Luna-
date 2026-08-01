import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable } from 'rxjs';
import { AuthUser } from '../decorators/current-user.decorator';
import { tenantStorage } from '../../prisma/tenant-context';

/**
 * Кладёт company_id авторизованного пользователя в AsyncLocalStorage,
 * откуда его берёт Prisma-middleware.
 *
 * Реализовано интерцептором, а не guard'ом: guard завершает свой стек вызовов
 * до выполнения обработчика, поэтому als.run() внутри него не «накрыл» бы
 * контроллер. Интерцептор оборачивает всю оставшуюся цепочку целиком.
 */
@Injectable()
export class TenantInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const { user } = context.switchToHttp().getRequest<{ user?: AuthUser }>();

    if (!user?.companyId) return next.handle();

    return tenantStorage.run(
      { companyId: user.companyId, userId: user.userId, role: user.role },
      () => next.handle(),
    );
  }
}
