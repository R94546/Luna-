import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { requireTenant } from '../../prisma/tenant-context';

/** Сутки — столько живёт ключ. Столько же обещано клиенту в ТЗ. */
const TTL_MS = 24 * 60 * 60 * 1000;

const CLEANUP_MS = 60 * 60 * 1000;

/** Что нашлось по ключу: готовый ответ, выполняющийся запрос или ничего. */
export type Lookup =
  | { state: 'fresh' }
  | { state: 'in_flight' }
  | { state: 'conflict' }
  | { state: 'replay'; statusCode: number; response: unknown };

@Injectable()
export class IdempotencyService {
  private readonly logger = new Logger(IdempotencyService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Хеш тела запроса.
   *
   * Ключи в JSON сортируются: клиент не обязан слать поля в одном и том же
   * порядке, а `{a,b}` и `{b,a}` — один и тот же запрос. Без сортировки
   * добросовестный повтор выглядел бы как подмена тела.
   */
  hashBody(body: unknown): string {
    return createHash('sha256').update(stableStringify(body)).digest('hex');
  }

  /**
   * Занимает ключ под выполняющийся запрос либо сообщает, что с ним делать.
   *
   * Занятие — это INSERT с уникальным индексом, а не «проверил и вставил»:
   * два нажатия подряд приходят почти одновременно, и между проверкой
   * и вставкой второй запрос успел бы проскочить. Здесь гонку разрешает
   * база: второй INSERT падает на уникальности, и мы уже знаем, что
   * происходит с первым.
   */
  async claim(endpoint: string, key: string, requestHash: string): Promise<Lookup> {
    const { companyId } = requireTenant();

    // createMany + skipDuplicates вместо create в try/catch: тот же один
    // запрос, но занятый ключ не порождает исключение и не сорит
    // `prisma:error` в логах при каждом штатном повторе.
    const { count } = await this.prisma.idempotencyKey.createMany({
      data: [
        {
          companyId,
          endpoint,
          key,
          requestHash,
          expiresAt: new Date(Date.now() + TTL_MS),
        },
      ],
      skipDuplicates: true,
    });

    if (count === 1) return { state: 'fresh' };

    const existing = await this.prisma.idempotencyKey.findFirst({
      where: { endpoint, key },
    });

    // Ключ протух между вставкой и чтением — редко, но возможно.
    if (!existing) return { state: 'fresh' };

    // Тот же ключ с другим телом — ошибка клиента, а не повтор. Молча
    // вернуть чужой результат было бы хуже честного отказа.
    if (existing.requestHash !== requestHash) return { state: 'conflict' };

    if (existing.statusCode === null) return { state: 'in_flight' };

    return {
      state: 'replay',
      statusCode: existing.statusCode,
      response: existing.response,
    };
  }

  /** Запоминает результат: следующий повтор получит его вместо выполнения. */
  async complete(
    endpoint: string,
    key: string,
    statusCode: number,
    response: unknown,
  ): Promise<void> {
    await this.prisma.idempotencyKey.updateMany({
      where: { endpoint, key },
      data: { statusCode, response: response as Prisma.InputJsonValue },
    });
  }

  /**
   * Освобождает ключ после неудачи.
   *
   * Запомнить ошибку было бы неправильно: сеть отвалилась, склад не хватило,
   * пользователь исправил и жмёт снова — он вправе получить новую попытку,
   * а не сутки видеть первую ошибку.
   */
  async release(endpoint: string, key: string): Promise<void> {
    await this.prisma.idempotencyKey.deleteMany({ where: { endpoint, key } });
  }

  /**
   * Уборка протухших ключей.
   *
   * Без неё таблица растёт на каждую денежную операцию и не уменьшается
   * никогда. Сутки после истечения записи уже ни на что не влияют, а место
   * и время на индексе занимают.
   */
  @Interval(CLEANUP_MS)
  async cleanupExpired(): Promise<void> {
    // Без tenant-контекста: уборка идёт по всем компаниям сразу, это
    // единственное обращение к таблице, которому фильтр не нужен.
    const { count } = await this.prisma.idempotencyKey.deleteMany({
      where: { expiresAt: { lt: new Date() } },
    });

    if (count > 0) this.logger.debug(`Удалено просроченных ключей: ${count}`);
  }
}

/**
 * JSON с отсортированными ключами на всех уровнях.
 *
 * `JSON.stringify` сохраняет порядок вставки, а он у клиента может меняться
 * от сборки к сборке — хеш поехал бы вместе с ним.
 */
function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';

  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;

  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`);

  return `{${entries.join(',')}}`;
}
