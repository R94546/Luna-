import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const config = app.get(ConfigService);
  const logger = new Logger('Bootstrap');

  app.setGlobalPrefix('api/v1');
  app.use(helmet());

  const origins = config.get<string>('CORS_ORIGINS', '*');
  app.enableCors({
    origin: origins === '*' ? true : origins.split(',').map((o) => o.trim()),
    credentials: true,
  });

  // Глобальный ValidationPipe не подключаем: валидация идёт через zod-схемы
  // (ZodValidationPipe на каждом эндпоинте), и тянуть class-validator ради
  // второго, параллельного механизма проверки — лишняя зависимость и путаница.

  // Telegram шлёт вебхуки без keep-alive; корректное завершение нужно,
  // чтобы при деплое не оборвать транзакцию на середине.
  app.enableShutdownHooks();

  const port = config.get<number>('PORT', 3000);
  await app.listen(port);

  logger.log(`Luna API запущен: http://localhost:${port}/api/v1`);
}

void bootstrap();
