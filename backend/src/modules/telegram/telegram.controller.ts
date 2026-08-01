import { Body, Controller, ForbiddenException, Headers, HttpCode, Param, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Update } from 'grammy/types';
import { Public } from '../../common/decorators/public.decorator';
import { TelegramService } from './telegram.service';

@Controller('telegram')
export class TelegramController {
  constructor(
    private readonly telegram: TelegramService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Приём апдейтов от Telegram.
   *
   * Двойная защита: секретный сегмент пути и заголовок, который Telegram
   * присылает сам. Путь может попасть в логи прокси, заголовок — нет,
   * поэтому одного механизма мало.
   *
   * Отвечаем 200 всегда, когда апдейт принят: любой другой код заставит
   * Telegram повторять доставку, а обработка уже идемпотентна.
   */
  @Public()
  @Post('webhook/:secret')
  @HttpCode(200)
  async webhook(
    @Param('secret') secret: string,
    @Headers('x-telegram-bot-api-secret-token') headerToken: string | undefined,
    @Body() update: Update,
  ): Promise<{ ok: true }> {
    const expected = this.config.get<string>('TELEGRAM_WEBHOOK_SECRET', '');

    if (!expected || secret !== expected || headerToken !== expected) {
      throw new ForbiddenException();
    }

    await this.telegram.handleUpdate(update);
    return { ok: true };
  }
}
