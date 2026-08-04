import { createWriteStream } from 'node:fs';
import { createRequire } from 'node:module';
import PDFDocument from 'pdfkit';
import { ReportDocument, ReportTable, formatDate, money } from '../report-document';

/**
 * Шрифт с кириллицей.
 *
 * Встроенные шрифты PDF (Helvetica и прочие) кодируются в WinAnsi, где
 * кириллицы нет: «Зарплата» вышла бы набором вопросительных знаков.
 * Roboto приходит пакетом, fontkit внутри pdfkit читает .woff наравне
 * с .ttf — отдельного файла в репозитории для этого не нужно.
 *
 * Именно `roboto-fontface`, а не `@fontsource/roboto`: последний режет
 * шрифт по unicode-диапазонам, и в кириллическом куске нет ни латиницы,
 * ни цифр. Для веба это правильно — браузер подставит нужный кусок сам,
 * — но PDF так не умеет: артикул «SP-12» и сумма вышли бы квадратами
 * при совершенно читаемом заголовке.
 */
export const FONT_REGULAR = 'roboto-fontface/fonts/roboto/Roboto-Regular.woff';
export const FONT_BOLD = 'roboto-fontface/fonts/roboto/Roboto-Bold.woff';

/** Тип документа берём от самого класса: глобального `PDFKit` линтер не знает. */
type Pdf = InstanceType<typeof PDFDocument>;

const PAGE_MARGIN = 36;
const FONT_SIZE = 8;
const ROW_HEIGHT = 14;

export function buildPdf(document: ReportDocument, filePath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    // Альбомная ориентация: в отчёте по продажам семь колонок, и в портрет
    // они влезают только нечитаемым кеглем.
    const pdf = new PDFDocument({ size: 'A4', layout: 'landscape', margin: PAGE_MARGIN });
    const stream = createWriteStream(filePath);

    stream.on('finish', () => resolve());
    stream.on('error', reject);
    pdf.on('error', reject);

    pdf.pipe(stream);

    const require = createRequire(__filename);
    pdf.registerFont('regular', require.resolve(FONT_REGULAR));
    pdf.registerFont('bold', require.resolve(FONT_BOLD));

    pdf.font('bold').fontSize(16).text(document.title);
    pdf.font('regular').fontSize(10).text(document.subtitle);
    pdf.moveDown(0.5);
    pdf
      .fontSize(8)
      .fillColor('#888888')
      .text(`Сформирован ${formatDate(new Date())}`)
      .fillColor('#000000');

    for (const table of document.tables) {
      drawTable(pdf, table);
    }

    pdf.end();
  });
}

function drawTable(pdf: Pdf, table: ReportTable): void {
  const usableWidth = pdf.page.width - PAGE_MARGIN * 2;
  const totalUnits = table.columns.reduce((acc, column) => acc + column.width, 0);
  const widths = table.columns.map((column) => (column.width / totalUnits) * usableWidth);

  pdf.moveDown(1);
  pdf.font('bold').fontSize(11).text(table.title);
  pdf.moveDown(0.3);

  if (table.rows.length === 0) {
    pdf.font('regular').fontSize(9).fillColor('#888888');
    pdf.text(table.emptyText ?? 'Данных нет').fillColor('#000000');
    return;
  }

  drawRow(pdf, table, widths, table.columns.map((column) => column.header), true);

  for (const row of table.rows) {
    // Заголовок таблицы на новой странице не повторяется намеренно: он бы
    // разорвал длинную ведомость на куски, у которых не видно, где начало.
    if (pdf.y > pdf.page.height - PAGE_MARGIN - ROW_HEIGHT * 2) {
      pdf.addPage();
    }

    drawRow(pdf, table, widths, row, false);
  }

  if (table.total) {
    drawRow(pdf, table, widths, table.total, true);
  }
}

function drawRow(
  pdf: Pdf,
  table: ReportTable,
  widths: number[],
  cells: (string | number | null)[],
  bold: boolean,
): void {
  const top = pdf.y;
  let left = PAGE_MARGIN;

  pdf.font(bold ? 'bold' : 'regular').fontSize(FONT_SIZE);

  table.columns.forEach((column, index) => {
    const raw = cells[index];
    const text =
      raw === null || raw === undefined
        ? ''
        : column.money && typeof raw === 'number'
          ? money(raw)
          : String(raw);

    pdf.text(text, left + 2, top + 3, {
      width: widths[index] - 4,
      align: column.align ?? 'left',
      // Без ellipsis длинная строка позиций растянула бы строку таблицы
      // на три этажа и разъехалась с соседними колонками.
      ellipsis: true,
      height: ROW_HEIGHT - 4,
    });

    left += widths[index];
  });

  const bottom = top + ROW_HEIGHT;

  pdf
    .moveTo(PAGE_MARGIN, bottom)
    .lineTo(pdf.page.width - PAGE_MARGIN, bottom)
    .lineWidth(0.3)
    .strokeColor(bold ? '#666666' : '#dddddd')
    .stroke();

  pdf.y = bottom;
  pdf.x = PAGE_MARGIN;
}
