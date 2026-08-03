import { changePercent, customPeriod, isoDate, previousPeriod, resolvePeriod } from './period';

/** Среда, 12 августа 2026. Середина недели, месяца, квартала и года. */
const NOW = new Date('2026-08-12T14:30:00.000Z');

describe('границы периодов', () => {
  it('месяц — с первого по последнее число', () => {
    const { from, to, label } = resolvePeriod('month', NOW);

    expect(isoDate(from)).toBe('2026-08-01');
    expect(isoDate(to)).toBe('2026-08-31');
    expect(label).toBe('Avgust 2026');
  });

  it('квартал — три месяца', () => {
    const { from, to, label } = resolvePeriod('quarter', NOW);

    expect(isoDate(from)).toBe('2026-07-01');
    expect(isoDate(to)).toBe('2026-09-30');
    expect(label).toBe('3-chorak 2026');
  });

  it('год — с января по декабрь', () => {
    const { from, to, label } = resolvePeriod('year', NOW);

    expect(isoDate(from)).toBe('2026-01-01');
    expect(isoDate(to)).toBe('2026-12-31');
    expect(label).toBe('2026');
  });

  /** В цехе неделя начинается с понедельника, а не с воскресенья. */
  it('неделя — с понедельника по воскресенье', () => {
    const { from, to } = resolvePeriod('week', NOW);

    expect(isoDate(from)).toBe('2026-08-10');
    expect(isoDate(to)).toBe('2026-08-16');
  });

  it('воскресенье относится к уходящей неделе, а не к следующей', () => {
    const sunday = new Date('2026-08-16T10:00:00.000Z');
    const { from, to } = resolvePeriod('week', sunday);

    expect(isoDate(from)).toBe('2026-08-10');
    expect(isoDate(to)).toBe('2026-08-16');
  });

  /**
   * Правая граница — конец дня. `sold_at` это момент времени, и продажа
   * в 23:50 последнего числа обязана попасть в отчёт, а не выпасть из него.
   */
  it('правая граница включает весь последний день', () => {
    const { to } = resolvePeriod('month', NOW);

    expect(to.getUTCHours()).toBe(23);
    expect(to.getUTCMinutes()).toBe(59);
    expect(new Date('2026-08-31T23:50:00.000Z') <= to).toBe(true);
  });

  it('левая граница начинается с полуночи', () => {
    const { from } = resolvePeriod('month', NOW);

    expect(from.getUTCHours()).toBe(0);
    expect(from.toISOString()).toBe('2026-08-01T00:00:00.000Z');
  });

  it('февраль високосного года заканчивается 29-м', () => {
    const { to } = resolvePeriod('month', new Date('2028-02-10T00:00:00.000Z'));

    expect(isoDate(to)).toBe('2028-02-29');
  });

  it('декабрь не перетекает в следующий год', () => {
    const { from, to } = resolvePeriod('month', new Date('2026-12-15T00:00:00.000Z'));

    expect(isoDate(from)).toBe('2026-12-01');
    expect(isoDate(to)).toBe('2026-12-31');
  });

  it('произвольный период берётся как задан', () => {
    const { from, to, label } = customPeriod('2026-03-05', '2026-03-20');

    expect(isoDate(from)).toBe('2026-03-05');
    expect(isoDate(to)).toBe('2026-03-20');
    expect(label).toBe('2026-03-05 — 2026-03-20');
  });
});

describe('предыдущий период', () => {
  /**
   * Сравнение идёт с периодом ТОЙ ЖЕ ДЛИНЫ, а не с прошлым календарным
   * месяцем. Иначе третьего числа неполный текущий месяц сравнивался бы
   * с полным прошлым, и владелец каждый месяц видел бы обвал на 90%.
   */
  it('той же длины, что и текущий', () => {
    const current = customPeriod('2026-08-01', '2026-08-31');
    const before = previousPeriod(current);

    const lengthOf = (p: { from: Date; to: Date }) => p.to.getTime() - p.from.getTime();

    expect(lengthOf(before)).toBe(lengthOf(current));
  });

  it('заканчивается ровно перед началом текущего', () => {
    const current = customPeriod('2026-08-01', '2026-08-31');
    const before = previousPeriod(current);

    expect(before.to.getTime()).toBe(current.from.getTime() - 1);
  });

  it('не пересекается с текущим', () => {
    const current = resolvePeriod('month', NOW);
    const before = previousPeriod(current);

    expect(before.to < current.from).toBe(true);
  });

  /** 1–10 августа это десять дней, значит и предыдущий отрезок — 22–31 июля. */
  it('для неполного периода отсчитывает столько же дней', () => {
    const current = customPeriod('2026-08-01', '2026-08-10');
    const before = previousPeriod(current);

    expect(isoDate(before.from)).toBe('2026-07-22');
    expect(isoDate(before.to)).toBe('2026-07-31');
  });

  it('считает дни, а не миллисекунды: границы обоих отрезков — целые сутки', () => {
    const current = customPeriod('2026-08-01', '2026-08-10');
    const before = previousPeriod(current);

    const days = (p: { from: Date; to: Date }) =>
      Math.round((p.to.getTime() - p.from.getTime() + 1) / 86_400_000);

    expect(days(before)).toBe(10);
    expect(days(current)).toBe(10);
  });
});

describe('changePercent', () => {
  it('считает рост', () => {
    expect(changePercent(120, 100)).toBe(20);
  });

  it('считает падение', () => {
    expect(changePercent(80, 100)).toBe(-20);
  });

  it('округляет до десятых', () => {
    expect(changePercent(112.4567, 100)).toBe(12.5);
  });

  it('ноль изменений — ноль процентов', () => {
    expect(changePercent(100, 100)).toBe(0);
  });

  /**
   * Рост с нуля процентами не выражается: делить на ноль нельзя, а «+100%»
   * или «+∞%» одинаково выдуманы. Клиент по null рисует прочерк.
   */
  it('рост с нуля — null, а не выдуманная цифра', () => {
    expect(changePercent(50000, 0)).toBeNull();
  });

  it('ноль из нуля — тоже null', () => {
    expect(changePercent(0, 0)).toBeNull();
  });

  it('падение до нуля — минус сто процентов', () => {
    expect(changePercent(0, 100)).toBe(-100);
  });

  /**
   * Прошлый период в минусе (цех отработал в убыток). Знаменатель берётся
   * по модулю, иначе рост убытка показался бы улучшением.
   */
  it('работает от отрицательной базы', () => {
    expect(changePercent(-50, -100)).toBe(50);
    expect(changePercent(-150, -100)).toBe(-50);
  });

  it('переваривает строки — суммы приходят из Decimal', () => {
    expect(changePercent('84300000', '75000000')).toBe(12.4);
  });
});
