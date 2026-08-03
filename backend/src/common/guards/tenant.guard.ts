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
 *
 * Контекст ставится вокруг ПОДПИСКИ, а не вокруг вызова `next.handle()`.
 * Разница неочевидная и дорогая: `handle()` только строит Observable
 * и сразу возвращает управление, после чего `run()` завершается и контекст
 * снимается. Пока вся работа ниже была синхронной, это сходило с рук —
 * обработчик успевал отработать внутри той же подписки. Первый же
 * интерцептор с промисом посередине ломал цепочку: после await контекста
 * уже не было, и Prisma-middleware переставал фильтровать по компании.
 *
 * Обёртка вокруг subscribe() держит scope на всё время выполнения, включая
 * продолжения промисов, — они наследуют контекст от места создания.
 */
@Injectable()
export class TenantInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const { user } = context.switchToHttp().getRequest<{ user?: AuthUser }>();

    if (!user?.companyId) return next.handle();

    const tenant = { companyId: user.companyId, userId: user.userId, role: user.role };

    return new Observable((subscriber) =>
      tenantStorage.run(tenant, () => next.handle().subscribe(subscriber)),
    );
  }
}
