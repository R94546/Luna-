import ExcelJS from 'exceljs';
import { ReportDocument, ReportTable } from '../report-document';

/** Формат сумм: разряды пробелами, без копеек — как в приложении. */
const MONEY_FORMAT = '# ##0';

/**
 * XLSX: каждая таблица отчёта — отдельный лист.
 *
 * Суммы пишутся числами, а не строками: отчёт открывают, чтобы досчитать
 * своё — отфильтровать, просуммировать, построить сводную. Текст «1 200 000»
 * в ячейке всё это ломает.
 */
export async function buildXlsx(document: ReportDocument, filePath: string): Promise<void> {
  const workbook = new ExcelJS.Workbook();
  workbook.created = new Date();

  for (const table of document.tables) {
    addSheet(workbook, document, table);
  }

  await workbook.xlsx.writeFile(filePath);
}

function addSheet(
  workbook: ExcelJS.Workbook,
  document: ReportDocument,
  table: ReportTable,
): void {
  // Имя листа в Excel — до 31 символа, и запрещены : \ / ? * [ ]
  const sheet = workbook.addWorksheet(table.title.replace(/[:\\/?*[\]]/g, ' ').slice(0, 31));

  sheet.addRow([document.title]).font = { bold: true, size: 14 };
  sheet.addRow([document.subtitle]);
  sheet.addRow([]);

  const header = sheet.addRow(table.columns.map((column) => column.header));
  header.font = { bold: true };

  sheet.columns.forEach((column, index) => {
    column.width = table.columns[index]?.width ?? 16;
  });

  if (table.rows.length === 0 && table.emptyText) {
    sheet.addRow([table.emptyText]);
    return;
  }

  for (const row of table.rows) {
    const added = sheet.addRow(row.map((cell) => cell ?? ''));
    applyFormats(added, table);
  }

  if (table.total) {
    const total = sheet.addRow(table.total.map((cell) => cell ?? ''));
    total.font = { bold: true };
    applyFormats(total, table);
  }

  // Шапка остаётся видимой при прокрутке: в отчёте за год строк сотни,
  // и без закрепления через экран уже не понять, что за колонка.
  sheet.views = [{ state: 'frozen', ySplit: 4 }];
}

function applyFormats(row: ExcelJS.Row, table: ReportTable): void {
  table.columns.forEach((column, index) => {
    const cell = row.getCell(index + 1);

    if (column.money) cell.numFmt = MONEY_FORMAT;
    if (column.align === 'right') cell.alignment = { horizontal: 'right' };
  });
}
