/** Именованные периоды, которыми мыслит владелец на главном экране. */
export type PeriodName = 'week' | 'month' | 'quarter' | 'year';

export interface Period {
  from: Date;
  to: Date;
  label: string;
}

const MONTHS_UZ = [
  'Yanvar',
  'Fevral',
  'Mart',
  'Aprel',
  'May',
  'Iyun',
  'Iyul',
  'Avgust',
  'Sentyabr',
  'Oktyabr',
  'Noyabr',
  'Dekabr',
];

/**
 * Границы периода.
 *
 * Всё в UTC и по календарным суткам: `sold_at` — момент времени, и продажа
 * в 23:50 последнего дня месяца обязана попасть в этот месяц, а не выпасть
 * из отчёта. Правая граница поэтому конец дня, а не полночь.
 */
export function resolvePeriod(name: PeriodName, now = new Date()): Period {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();

  switch (name) {
    case 'week': {
      // Неделя с понедельника: в цехе неделя начинается с него, и сдвиг
      // на воскресенье (как в JS по умолчанию) разрежет её пополам.
      const day = now.getUTCDay();
      const shift = day === 0 ? 6 : day - 1;
      const from = startOfDay(new Date(Date.UTC(year, month, now.getUTCDate() - shift)));
      const to = endOfDay(new Date(Date.UTC(year, month, now.getUTCDate() - shift + 6)));
      return { from, to, label: `${isoDate(from)} — ${isoDate(to)}` };
    }

    case 'month': {
      const from = startOfDay(new Date(Date.UTC(year, month, 1)));
      const to = endOfDay(new Date(Date.UTC(year, month + 1, 0)));
      return { from, to, label: `${MONTHS_UZ[month]} ${year}` };
    }

    case 'quarter': {
      const first = Math.floor(month / 3) * 3;
      const from = startOfDay(new Date(Date.UTC(year, first, 1)));
      const to = endOfDay(new Date(Date.UTC(year, first + 3, 0)));
      return { from, to, label: `${Math.floor(month / 3) + 1}-chorak ${year}` };
    }

    case 'year': {
      const from = startOfDay(new Date(Date.UTC(year, 0, 1)));
      const to = endOfDay(new Date(Date.UTC(year, 12, 0)));
      return { from, to, label: String(year) };
    }
  }
}

export function customPeriod(dateFrom: string, dateTo: string): Period {
  const from = startOfDay(new Date(dateFrom));
  const to = endOfDay(new Date(dateTo));
  return { from, to, label: `${dateFrom} — ${dateTo}` };
}

/**
 * Предыдущий период той же длины.
 *
 * Именно длины, а не «прошлый календарный месяц»: сравнивать неполный
 * текущий месяц с полным прошлым — значит каждый раз в начале месяца
 * показывать владельцу обвал на 90%.
 */
export function previousPeriod(period: Period): Period {
  const span = period.to.getTime() - period.from.getTime();

  return {
    from: new Date(period.from.getTime() - span - 1),
    to: new Date(period.from.getTime() - 1),
    label: 'oldingi davr',
  };
}

/**
 * Изменение в процентах.
 *
 * Рост с нуля не выражается процентами: делить на ноль нельзя, а рисовать
 * «+∞%» или «+100%» одинаково бессмысленно. Возвращаем null, и клиент
 * показывает прочерк вместо выдуманной цифры.
 */
export function changePercent(current: string | number, previous: string | number): number | null {
  const now = Number(current);
  const before = Number(previous);

  if (before === 0) return null;

  return Math.round(((now - before) / Math.abs(before)) * 1000) / 10;
}

export function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function startOfDay(date: Date): Date {
  const copy = new Date(date);
  copy.setUTCHours(0, 0, 0, 0);
  return copy;
}

function endOfDay(date: Date): Date {
  const copy = new Date(date);
  copy.setUTCHours(23, 59, 59, 999);
  return copy;
}
