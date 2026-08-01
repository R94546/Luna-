import { AsyncLocalStorage } from 'node:async_hooks';

export interface TenantContext {
  companyId: string;
  userId?: string;
  role?: string;
}

/**
 * Контекст арендатора, «протянутый» через весь стек вызовов без передачи
 * параметром. Заполняется TenantGuard из JWT, а для фоновых задач
 * (Telegram-воркер, крон) — явно через runWithTenant.
 */
export const tenantStorage = new AsyncLocalStorage<TenantContext>();

export function getTenant(): TenantContext | undefined {
  return tenantStorage.getStore();
}

export function requireTenant(): TenantContext {
  const ctx = tenantStorage.getStore();
  if (!ctx) {
    // Означает баг: сервис вызван вне HTTP-запроса и без runWithTenant.
    // Лучше упасть, чем молча выполнить запрос по всем компаниям сразу.
    throw new Error('Tenant-контекст отсутствует. Оберните вызов в runWithTenant().');
  }
  return ctx;
}

export function runWithTenant<T>(ctx: TenantContext, fn: () => Promise<T>): Promise<T> {
  return tenantStorage.run(ctx, fn);
}
