import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';

/** Шаг диалога. Между сообщениями бот помнит, чего он ждёт от рабочего. */
export type Step = 'idle' | 'awaiting_quantity';

export interface Session {
  step: Step;
  productId?: string;
  operationId?: string;
  updatedAt: number;
}

const SESSION_TTL_MS = 30 * 60_000;
const SESSION_CLEANUP_MS = 10 * 60_000;

/**
 * Состояние незавершённых диалогов.
 *
 * Хранится в памяти процесса. Осознанное ограничение: при нескольких
 * инстансах API рабочий, попавший на другой инстанс, потеряет незавершённый
 * шаг и начнёт заново. Для одного инстанса (а это весь горизонт MVP) этого
 * достаточно; при масштабировании меняется только реализация этого сервиса —
 * обработчики к нему обращаются через методы и о хранилище не знают.
 */
@Injectable()
export class TelegramSessionService {
  private readonly logger = new Logger(TelegramSessionService.name);
  private readonly sessions = new Map<number, Session>();

  /** Возвращает живую сессию либо заводит новую, если прежняя протухла. */
  get(tgId: number): Session {
    const existing = this.sessions.get(tgId);

    if (existing && Date.now() - existing.updatedAt < SESSION_TTL_MS) {
      existing.updatedAt = Date.now();
      return existing;
    }

    const fresh: Session = { step: 'idle', updatedAt: Date.now() };
    this.sessions.set(tgId, fresh);
    return fresh;
  }

  clear(tgId: number): void {
    this.sessions.delete(tgId);
  }

  /**
   * Уборка протухших диалогов.
   *
   * `get()` подменяет протухшую сессию новой, но только когда тот же
   * рабочий напишет снова. Бросивший диалог на середине не возвращается —
   * и его запись остаётся в памяти навсегда.
   */
  @Interval(SESSION_CLEANUP_MS)
  cleanupExpired(): void {
    const now = Date.now();
    let removed = 0;

    for (const [tgId, session] of this.sessions) {
      if (now - session.updatedAt >= SESSION_TTL_MS) {
        this.sessions.delete(tgId);
        removed++;
      }
    }

    if (removed > 0) {
      this.logger.debug(`Очищено просроченных сессий: ${removed}`);
    }
  }

  /** Размер хранилища — для диагностики и тестов. */
  get size(): number {
    return this.sessions.size;
  }
}
