import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request, Response } from 'express';
import { Observable, catchError, concatMap, from, of, switchMap, throwError } from 'rxjs';
import { IDEMPOTENT_KEY } from '../decorators/idempotent.decorator';
import { AppException } from '../filters/app.exception';
import { IdempotencyService } from './idempotency.service';

const HEADER = 'idempotency-key';

/** Заголовок, по которому клиент видит, что ответ — повтор, а не новая запись. */
const REPLAY_HEADER = 'Idempotent-Replay';

/**
 * Повтор денежной операции возвращает первый результат вместо второй записи.
 *
 * Реализовано интерцептором, а не guard'ом: guard умеет только пропустить
 * или отклонить, а здесь надо ещё и подменить ответ уже выполненным,
 * и запомнить результат после успеха.
 *
 * Регистрируется после TenantInterceptor — ключи хранятся по компаниям,
 * и без tenant-контекста запрос к таблице не отфильтруется.
 */
@Injectable()
export class IdempotencyInterceptor implements NestInterceptor {
  constructor(
    private readonly reflector: Reflector,
    private readonly idempotency: IdempotencyService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const isIdempotent = this.reflector.getAllAndOverride<boolean>(IDEMPOTENT_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!isIdempotent) return next.handle();

    const request = context.switchToHttp().getRequest<Request>();
    const key = request.header(HEADER)?.trim();

    // Заголовка нет — работаем как раньше. Клиент, который его не шлёт,
    // ничего не теряет по сравнению с версией без идемпотентности.
    if (!key) return next.handle();

    const endpoint = request.route?.path ?? request.path;
    const hash = this.idempotency.hashBody(request.body);

    return from(this.idempotency.claim(endpoint, key, hash)).pipe(
      switchMap((lookup) => {
        if (lookup.state === 'conflict') {
          throw new AppException(
            409,
            'IDEMPOTENCY_KEY_REUSED',
            'error.idempotency_key_reused',
          );
        }

        // Первый запрос ещё выполняется. Отдать «успешно» нельзя — результата
        // пока нет; отдать ошибку тоже неверно — операция, возможно, пройдёт.
        // 409 с внятным текстом честнее всего: клиент повторит через секунду
        // и получит либо готовый ответ, либо настоящую ошибку.
        if (lookup.state === 'in_flight') {
          throw new AppException(
            409,
            'IDEMPOTENCY_IN_PROGRESS',
            'error.idempotency_in_progress',
          );
        }

        if (lookup.state === 'replay') {
          const response = context.switchToHttp().getResponse<Response>();
          response.status(lookup.statusCode);
          response.setHeader(REPLAY_HEADER, 'true');
          return of(lookup.response);
        }

        return next.handle().pipe(
          // Результат записывается ДО отдачи ответа, а не параллельно с ней:
          // иначе повтор, пришедший сразу следом, застал бы ключ ещё пустым
          // и получил бы «запрос выполняется» вместо готового ответа.
          concatMap((result) => {
            const status = context.switchToHttp().getResponse<Response>().statusCode;
            return from(this.idempotency.complete(endpoint, key, status, result)).pipe(
              switchMap(() => of(result)),
            );
          }),
          // Ключ освобождается: пользователь исправил данные и жмёт снова —
          // он вправе получить новую попытку, а не сутки видеть первую ошибку.
          catchError((error: unknown) =>
            from(this.idempotency.release(endpoint, key)).pipe(
              switchMap(() => throwError(() => error)),
            ),
          ),
        );
      }),
    );
  }
}
