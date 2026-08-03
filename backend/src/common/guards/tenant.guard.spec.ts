import { CallHandler, ExecutionContext } from '@nestjs/common';
import { Observable, defer, firstValueFrom, from, of, switchMap } from 'rxjs';
import { getTenant } from '../../prisma/tenant-context';
import { AuthUser } from '../decorators/current-user.decorator';
import { TenantInterceptor } from './tenant.guard';

const USER: AuthUser = {
  userId: 'u-1',
  companyId: 'c-1',
  role: 'OWNER',
} as AuthUser;

function contextWith(user?: AuthUser): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as unknown as ExecutionContext;
}

/** Обработчик, который читает контекст в указанный момент своей работы. */
function handlerReading(readAt: 'sync' | 'after-await'): CallHandler {
  return {
    handle: () =>
      defer(async () => {
        if (readAt === 'after-await') {
          await new Promise((resolve) => setImmediate(resolve));
        }
        return getTenant();
      }),
  };
}

describe('TenantInterceptor', () => {
  const interceptor = new TenantInterceptor();

  it('ставит контекст компании', async () => {
    const tenant = await firstValueFrom(
      interceptor.intercept(contextWith(USER), handlerReading('sync')) as Observable<
        ReturnType<typeof getTenant>
      >,
    );

    expect(tenant).toMatchObject({ companyId: 'c-1', userId: 'u-1', role: 'OWNER' });
  });

  /**
   * Регрессия. Контекст обязан пережить await внутри обработчика.
   *
   * Раньше `run()` оборачивал только вызов `handle()` — он строит Observable
   * и сразу возвращает управление, после чего scope снимался, а подписка шла
   * уже без него. Пока всё ниже было синхронным, это сходило с рук; первый же
   * интерцептор с промисом посередине оставлял Prisma-middleware без company_id,
   * и запрос уходил в базу без фильтра по компании.
   */
  it('сохраняет контекст после await в обработчике', async () => {
    const tenant = await firstValueFrom(
      interceptor.intercept(contextWith(USER), handlerReading('after-await')) as Observable<
        ReturnType<typeof getTenant>
      >,
    );

    expect(tenant).toMatchObject({ companyId: 'c-1' });
  });

  /** Тот же случай, но await делает интерцептор выше по цепочке. */
  it('сохраняет контекст, когда промис вклинивается между интерцепторами', async () => {
    const downstream: CallHandler = {
      handle: () =>
        from(Promise.resolve('ключ занят')).pipe(
          switchMap(() => defer(async () => getTenant())),
        ),
    };

    const tenant = await firstValueFrom(
      interceptor.intercept(contextWith(USER), downstream) as Observable<
        ReturnType<typeof getTenant>
      >,
    );

    expect(tenant).toMatchObject({ companyId: 'c-1' });
  });

  /**
   * Без пользователя контекст не ставится: auth-слой работает до входа
   * в компанию, и требовать её там значит запретить вход в систему.
   */
  it('пропускает запрос без пользователя', async () => {
    const tenant = await firstValueFrom(
      interceptor.intercept(contextWith(undefined), handlerReading('sync')) as Observable<
        ReturnType<typeof getTenant>
      >,
    );

    expect(tenant).toBeUndefined();
  });

  it('не протекает контекстом наружу', async () => {
    await firstValueFrom(
      interceptor.intercept(contextWith(USER), handlerReading('sync')) as Observable<unknown>,
    );

    expect(getTenant()).toBeUndefined();
  });

  it('пробрасывает значение обработчика без изменений', async () => {
    const next: CallHandler = { handle: () => of({ items: [1, 2, 3] }) };

    const result = await firstValueFrom(
      interceptor.intercept(contextWith(USER), next) as Observable<unknown>,
    );

    expect(result).toEqual({ items: [1, 2, 3] });
  });

  it('пробрасывает ошибку обработчика', async () => {
    const next: CallHandler = {
      handle: () => defer(() => Promise.reject(new Error('сломалось'))),
    };

    await expect(
      firstValueFrom(interceptor.intercept(contextWith(USER), next) as Observable<unknown>),
    ).rejects.toThrow('сломалось');
  });
});
