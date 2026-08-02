import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import { createTenantMiddleware } from './tenant-middleware';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    super({
      log: [
        { emit: 'event', level: 'query' },
        { emit: 'stdout', level: 'warn' },
        { emit: 'stdout', level: 'error' },
      ],
    });

    this.$use(createTenantMiddleware());
  }

  async onModuleInit(): Promise<void> {
    await this.$connect();

    if (process.env.NODE_ENV === 'development') {
      // @ts-expect-error — типы событий Prisma не выводятся из динамического log-конфига
      this.$on('query', (e: Prisma.QueryEvent) => {
        if (e.duration > 100) {
          this.logger.warn(`Медленный запрос (${e.duration} мс): ${e.query}`);
        }
      });
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }

  /**
   * Инкремент пер-компанийного счётчика документов (заказ №14, продажа №203).
   *
   * INSERT ... ON CONFLICT DO UPDATE RETURNING — атомарно, одним запросом.
   * Строка счётчика блокируется до конца транзакции, поэтому два одновременных
   * заказа получат разные номера, а не одинаковые.
   *
   * Вызывать ТОЛЬКО внутри $transaction, передавая tx.
   */
  async nextNumber(
    tx: Prisma.TransactionClient,
    companyId: string,
    entity: 'order' | 'sale',
  ): Promise<number> {
    const rows = await tx.$queryRaw<{ last_value: number }[]>`
      INSERT INTO company_counters (company_id, entity, last_value)
      VALUES (${companyId}::uuid, ${entity}, 1)
      ON CONFLICT (company_id, entity)
      DO UPDATE SET last_value = company_counters.last_value + 1
      RETURNING last_value
    `;
    return rows[0].last_value;
  }
}
