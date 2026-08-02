import { Injectable } from '@nestjs/common';

/** Шаг диалога. Между сообщениями бот помнит, чего он ждёт от рабочего. */
export type Step = 'idle' | 'awaiting_quantity';

export interface Session {
  step: Step;
  productId?: string;
  operationId?: string;
  updatedAt: number;
}

const SESSION_TTL_MS = 30 * 60_000;

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
}
