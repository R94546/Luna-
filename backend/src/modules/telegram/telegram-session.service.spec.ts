import { TelegramSessionService } from './telegram-session.service';

const TTL_MS = 30 * 60_000;

describe('TelegramSessionService', () => {
  let sessions: TelegramSessionService;

  beforeEach(() => {
    jest.useFakeTimers();
    sessions = new TelegramSessionService();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('возвращает ту же сессию при повторном обращении', () => {
    const first = sessions.get(1);
    first.productId = 'p-1';

    expect(sessions.get(1).productId).toBe('p-1');
    expect(sessions.size).toBe(1);
  });

  it('держит сессии разных рабочих раздельно', () => {
    sessions.get(1).productId = 'p-1';
    sessions.get(2).productId = 'p-2';

    expect(sessions.get(1).productId).toBe('p-1');
    expect(sessions.get(2).productId).toBe('p-2');
  });

  it('продлевает жизнь сессии при каждом обращении', () => {
    sessions.get(1).productId = 'p-1';

    jest.advanceTimersByTime(TTL_MS - 1000);
    expect(sessions.get(1).productId).toBe('p-1');

    // Ещё столько же — но отсчёт пошёл заново от предыдущего обращения.
    jest.advanceTimersByTime(TTL_MS - 1000);
    expect(sessions.get(1).productId).toBe('p-1');
  });

  /**
   * Протухшая сессия обязана обнуляться, а не продолжаться: иначе рабочий,
   * вернувшийся к брошенному диалогу через час, отправил бы количество
   * в давно забытую модель.
   */
  it('заводит чистую сессию вместо протухшей', () => {
    const stale = sessions.get(1);
    stale.productId = 'p-1';
    stale.step = 'awaiting_quantity';

    jest.advanceTimersByTime(TTL_MS + 1);

    const fresh = sessions.get(1);
    expect(fresh.productId).toBeUndefined();
    expect(fresh.step).toBe('idle');
  });

  it('очищает сессию по clear', () => {
    sessions.get(1);
    sessions.clear(1);

    expect(sessions.size).toBe(0);
  });

  describe('уборка по расписанию', () => {
    /**
     * Ради чего уборка вообще нужна: get() подменяет протухшую сессию
     * только когда тот же рабочий напишет снова. Бросивший диалог
     * не возвращается — без уборки его запись живёт до перезапуска.
     */
    it('удаляет только протухшие, не трогая живые', () => {
      for (let i = 0; i < 100; i++) sessions.get(i);

      jest.advanceTimersByTime(TTL_MS + 1);

      // Половина рабочих написала снова — их сессии свежие.
      for (let i = 0; i < 50; i++) sessions.get(i);

      sessions.cleanupExpired();

      expect(sessions.size).toBe(50);
    });

    it('не трогает ничего, пока время не вышло', () => {
      for (let i = 0; i < 10; i++) sessions.get(i);

      jest.advanceTimersByTime(TTL_MS - 1);
      sessions.cleanupExpired();

      expect(sessions.size).toBe(10);
    });

    it('на пустом хранилище проходит без ошибок', () => {
      expect(() => sessions.cleanupExpired()).not.toThrow();
      expect(sessions.size).toBe(0);
    });
  });
});
