/**
 * Отчёты и уведомления на живой БД.
 *
 * Проверяется то, что не поймать модульным тестом: файл действительно
 * собирается по данным компании, кириллица в PDF не превращается в мусор,
 * фоновая генерация не теряет tenant-контекст (иначе в отчёт попали бы
 * чужие продажи), а сторож уведомлений не заваливает ленту повторами.
 *
 * Скрипт заводит свои данные в 2018 году, чтобы не смешаться с демо,
 * и убирает их за собой.
 *
 * Запуск:
 *   npm run test:reports
 */
import { readFileSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import ExcelJS from 'exceljs';
import { FONT_BOLD, FONT_REGULAR } from '../src/modules/reports/builders/pdf.builder';

/**
 * fontkit — тот самый разборщик шрифтов, которым пользуется pdfkit внутри.
 * Берём его через require, а не импортом: своих типов у него нет, а тянуть
 * @types ради одной проверки в ручном сценарии незачем.
 */
const nodeRequire = createRequire(__filename);
const fontkit = nodeRequire('fontkit') as {
  openSync(path: string): { hasGlyphForCodePoint(codePoint: number): boolean };
};
import { NotificationsCron } from '../src/modules/notifications/notifications.cron';
import { NotificationsService } from '../src/modules/notifications/notifications.service';
import { ReportDataService } from '../src/modules/reports/report-data.service';
import { ReportsService } from '../src/modules/reports/reports.service';
import { ExportReportDto, REPORT_TYPES } from '../src/modules/reports/dto/report.dto';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const reportData = new ReportDataService(prisma);
const reports = new ReportsService(reportData);
const notifications = new NotificationsService(prisma);
const cron = new NotificationsCron(prisma, notifications);

const MARKER = 'REPORTS-TEST';
const FROM = '2018-06-01';
const TO = '2018-06-30';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

function ok(label: string, condition: boolean, detail = ''): void {
  if (condition) passed++;
  else failed++;
  console.log(`  ${condition ? '✅' : '❌'} ${label}${detail ? `: ${detail}` : ''}`);
}

/** Ждёт, пока фоновая генерация закончится. */
async function waitReady(jobId: string): Promise<string> {
  for (let i = 0; i < 100; i++) {
    const job = reports.find(jobId);
    if (job.status !== 'PENDING') return job.status;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  return 'TIMEOUT';
}

async function main(): Promise<void> {
  const company = await prisma.company.findFirst({ where: { slug: 'luna-shoes' } });
  if (!company) {
    throw new Error('Компания luna-shoes не найдена — сначала выполните `npm run seed`.');
  }

  await reports.onModuleInit();
  await runWithTenant({ companyId: company.id }, () => scenario(company.id));
}

async function scenario(companyId: string): Promise<void> {
  await cleanup(companyId);

  // ── Данные, по которым считается отчёт ─────────────────────────────────
  const product = await prisma.product.create({
    data: {
      companyId,
      sku: `${MARKER}-SKU`,
      name: `${MARKER} model`,
      salePrice: '500000',
      costPrice: '300000',
      stockQuantity: 2,
      minStockLevel: 10,
    },
  });

  const account = await prisma.cashAccount.create({
    data: { companyId, name: `${MARKER} kassa`, balance: '0' },
  });

  const sale = await prisma.sale.create({
    data: {
      companyId,
      saleNumber: 90001,
      totalAmount: '1000000',
      paidAmount: '1000000',
      totalCost: '600000',
      soldAt: new Date(`${FROM}T10:00:00.000Z`),
      items: {
        create: {
          productId: product.id,
          quantity: 2,
          unitPrice: '500000',
          costPriceSnapshot: '300000',
          total: '1000000',
        },
      },
    },
  });

  await prisma.cashTransaction.create({
    data: {
      companyId,
      accountId: account.id,
      direction: 'IN',
      category: 'SALE',
      amount: '1000000',
      occurredAt: new Date(`${FROM}T10:00:00.000Z`),
      saleId: sale.id,
    },
  });

  // ── Сборка отчётов ──────────────────────────────────────────────────────
  console.log('\n=== Экспорт: все типы в XLSX ===');

  for (const type of REPORT_TYPES) {
    const dto: ExportReportDto = { type, format: 'XLSX', dateFrom: FROM, dateTo: TO };
    const job = reports.enqueue(dto);
    const status = await waitReady(job.jobId);

    const size = status === 'READY' ? statSync(reports.file(job.jobId).path).size : 0;
    ok(`${type}`, status === 'READY' && size > 0, `${status}, ${size} байт`);
  }

  console.log('\n=== Содержимое отчёта по продажам ===');

  const salesJob = reports.enqueue({
    type: 'SALES',
    format: 'XLSX',
    dateFrom: FROM,
    dateTo: TO,
  });
  await waitReady(salesJob.jobId);

  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(reports.file(salesJob.jobId).path);

  const sheet = workbook.worksheets[0];
  const rows = sheet.getSheetValues();
  const saleRow = rows.find(
    (row) => Array.isArray(row) && row.includes(90001),
  ) as (string | number)[] | undefined;

  ok('продажа попала в отчёт', saleRow !== undefined);
  check('сумма продажи', saleRow?.[5], 1000000);
  check('себестоимость', saleRow?.[6], 600000);
  // Прибыль считается в отчёте, а не берётся из базы: разойдись формула —
  // владелец увидит не ту цифру, по которой принимает решения.
  check('прибыль', saleRow?.[7], 400000);

  // Суммы обязаны быть числами: отчёт открывают, чтобы досчитать своё.
  ok('сумма записана числом', typeof saleRow?.[5] === 'number', typeof saleRow?.[5]);

  console.log('\n=== PDF ===');

  const pdfJob = reports.enqueue({
    type: 'PAYROLL',
    format: 'PDF',
    dateFrom: FROM,
    dateTo: TO,
  });
  const pdfStatus = await waitReady(pdfJob.jobId);
  ok('ведомость собралась', pdfStatus === 'READY', pdfStatus);

  if (pdfStatus === 'READY') {
    const bytes = readFileSync(reports.file(pdfJob.jobId).path);
    ok('это PDF', bytes.subarray(0, 4).toString() === '%PDF');
    // Кириллица в PDF живёт только со встроенным шрифтом: без него
    // «Зарплата» вышла бы вопросительными знаками, а файл всё равно
    // считался бы валидным.
    ok(
      'шрифт встроен',
      bytes.includes(Buffer.from('FontFile2')) || bytes.includes(Buffer.from('FontFile3')),
    );
  }

  // Проверка, купленная опытом: первый вариант брал шрифт из @fontsource,
  // а тот режет его по unicode-диапазонам. Заголовки печатались нормально,
  // а артикулы и суммы выходили квадратами — «PDF собрался» этого не ловит.
  checkGlyphs();

  console.log('\n=== Изоляция арендаторов ===');

  const otherJob = await runWithTenant({ companyId: OTHER_COMPANY }, async () => {
    try {
      reports.find(salesJob.jobId);
      return 'отдал';
    } catch {
      return 'не отдал';
    }
  });
  check('чужой отчёт', otherJob, 'не отдал');

  console.log('\n=== Уведомления ===');

  await prisma.notification.deleteMany({ where: { companyId, type: 'LOW_STOCK' } });

  await cron.run();
  const afterFirst = await prisma.notification.count({
    where: { companyId, type: 'LOW_STOCK' },
  });
  check('низкий остаток замечен', afterFirst >= 1, true);

  // Остаток остаётся низким неделями, крон ходит каждый час: без защиты
  // от повторов лента к пятнице состояла бы из одной этой строки.
  await cron.run();
  const afterSecond = await prisma.notification.count({
    where: { companyId, type: 'LOW_STOCK' },
  });
  check('повтор не создан', afterSecond, afterFirst);

  const user = await prisma.user.findFirst({ where: { companyId } });
  if (user) {
    const list = await notifications.findAll(user.id, { limit: 50 });
    ok('лента видна пользователю', list.items.length > 0, `${list.items.length} шт`);
    check('непрочитанных', list.unread > 0, true);

    await notifications.markAllRead(user.id);
    const after = await notifications.findAll(user.id, { limit: 50 });
    check('после «прочитать все»', after.unread, 0);

    // Прочитанное уведомление больше не блокирует новое: остаток так
    // и не пополнили, и владельца надо предупредить ещё раз.
    await cron.run();
    const revived = await notifications.findAll(user.id, { unreadOnly: true, limit: 50 });
    check('после прочтения приходит снова', revived.items.length > 0, true);
  }

  await cleanup(companyId);

  console.log(`\nИтог: ${passed} успешно, ${failed} провалено`);
  if (failed > 0) process.exitCode = 1;
}

/** Заведомо несуществующая компания — для проверки изоляции. */
const OTHER_COMPANY = '00000000-0000-0000-0000-0000000000ff';

/** Всё, что реально встречается в отчёте: имена, артикулы, суммы, знаки. */
const SAMPLE = 'Зарплата Ўзбекистон SP-12 1 200 000 № · — ()';

function checkGlyphs(): void {
  for (const font of [FONT_REGULAR, FONT_BOLD]) {
    const parsed = fontkit.openSync(nodeRequire.resolve(font));

    const missing = [...SAMPLE].filter(
      (char) => !parsed.hasGlyphForCodePoint(char.codePointAt(0) ?? 0),
    );

    ok(
      `шрифт покрывает алфавит (${font.split('/').pop()})`,
      missing.length === 0,
      missing.length > 0 ? `нет глифов: ${missing.join('')}` : '',
    );
  }
}

async function cleanup(companyId: string): Promise<void> {
  const products = await prisma.product.findMany({
    where: { companyId, sku: { startsWith: MARKER } },
    select: { id: true },
  });
  const productIds = products.map((p) => p.id);

  const sales = await prisma.sale.findMany({
    where: { companyId, saleNumber: 90001 },
    select: { id: true },
  });
  const saleIds = sales.map((s) => s.id);

  const accounts = await prisma.cashAccount.findMany({
    where: { companyId, name: { startsWith: MARKER } },
    select: { id: true },
  });
  const accountIds = accounts.map((a) => a.id);

  if (saleIds.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.saleItem.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.sale.deleteMany({ where: { id: { in: saleIds } } });
  }

  if (accountIds.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { accountId: { in: accountIds } } });
    await prisma.cashAccount.deleteMany({ where: { id: { in: accountIds } } });
  }

  if (productIds.length > 0) {
    await prisma.stockMovement.deleteMany({ where: { productId: { in: productIds } } });
    await prisma.product.deleteMany({ where: { id: { in: productIds } } });
  }

  await prisma.notification.deleteMany({ where: { companyId, type: 'LOW_STOCK' } });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
