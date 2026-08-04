/**
 * Промежуточное представление отчёта: таблицы, а не готовый файл.
 *
 * Без него каждый из пяти отчётов пришлось бы писать дважды — под XLSX
 * и под PDF, — и они разошлись бы в первый же месяц: колонку добавили
 * в Excel-версию, а в печатной её нет.
 */
export interface ReportColumn {
  header: string;
  /** Ширина в символах: XLSX задаёт её колонке, PDF — доле страницы. */
  width: number;
  align?: 'left' | 'right';
  /** Денежная колонка: в XLSX это число с форматом, в PDF — с разрядами. */
  money?: boolean;
}

export type ReportCell = string | number | null;

export interface ReportTable {
  title: string;
  columns: ReportColumn[];
  rows: ReportCell[][];
  /** Строка итогов: подписи в первой ячейке, дальше суммы по колонкам. */
  total?: ReportCell[];
  /** Показывается вместо таблицы, когда данных за период нет. */
  emptyText?: string;
}

export interface ReportDocument {
  title: string;
  subtitle: string;
  tables: ReportTable[];
}

/** «1 200 000». Неразрывный пробел, чтобы сумма не рвалась переносом. */
export function money(value: unknown): string {
  const amount = Math.round(Number(value ?? 0));
  const digits = Math.abs(amount).toString();
  let out = '';

  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ' ';
    out += digits[i];
  }

  return amount < 0 ? `-${out}` : out;
}

/** «04.08.2026» — как принято в накладных, а не ISO. */
export function formatDate(value: Date): string {
  const day = value.getDate().toString().padStart(2, '0');
  const month = (value.getMonth() + 1).toString().padStart(2, '0');

  return `${day}.${month}.${value.getFullYear()}`;
}
