import { Global, Module } from '@nestjs/common';
import { IdempotencyService } from './idempotency.service';

/**
 * Глобальный: интерцептор регистрируется в AppModule и должен видеть сервис,
 * не заставляя каждый модуль с денежным эндпоинтом импортировать этот.
 */
@Global()
@Module({
  providers: [IdempotencyService],
  exports: [IdempotencyService],
})
export class IdempotencyModule {}
