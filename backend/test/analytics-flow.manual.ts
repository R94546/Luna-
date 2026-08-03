/**
 * Аналитика на живой БД.
 *
 * Проверяется не «эндпоинт отвечает», а что цифры сходятся с тем, из чего
 * их собрали: прибыль равна выручке минус себестоимость, расходы и выплаты,
 * зарплата входит по выплатам, а сторнированная продажа выпадает отовсюду.
 * Ошибка здесь тихо врёт владельцу о том, сколько он заработал.
 *
 * Скрипт заводит свои данные в 2019 году, чтобы не смешаться с демо,
 * и убирает их за собой.
 *
 * Запуск:
 *   npm run test:analytics
 */
import { PaymentMethod, Prisma, SalaryPaymentType, WorkLogStatus } from '@prisma/client';
import { AnalyticsService } from '../src/modules/analytics/analytics.service';
import { CashService } from '../src/modules/cash/cash.service';
import { PayrollService } from '../src/modules/payroll/payroll.service';
import { SalaryPaymentsService } from '../src/modules/payroll/salary-payments.service';
import { SalesService } from '../src/modules/sales/sales.service';
import { StockService } from '../src/modules/stock/stock.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const stock = new StockService(prisma);
const cash = new CashService(prisma);
const sales = new SalesService(prisma, stock, cash);
const payroll = new PayrollService(prisma);
const payments = new SalaryPaymentsService(prisma, payroll, cash);
const analytics = new AnalyticsService(prisma);

const MARKER = 'ANALYTICS-TEST';
const FROM = '2019-11-01';
const TO = '2019-11-30';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

async function main(): Promise<void> {
  const company = await prisma.company.findFirst({ where: { slug: 'luna-shoes' } });
  if (!company) {
    throw new Error('Компания luna-shoes не найдена — сначала выполните `npm run seed`.');
  }

  await runWithTenant({ companyId: company.id }, () => scenario(company.id));
}

async function scenario(companyId: string): Promise<void> {
  await cleanup(companyId);

  const operation = await prisma.operation.create({
    data: { companyId, name: `${MARKER} op`, sortOrder: 998 },
  });
  const product = await prisma.product.create({
    data: {
      companyId,
      sku: `${MARKER}-SKU`,
      name: `${MARKER} model`,
      salePrice: '500000',
      costPrice: '300000',
      stockQuantity: 200,
    },
  });
  const account = await prisma.cashAccount.create({
    data: { companyId, name: `${MARKER} kassa`, balance: '0' },
  });
  const employee = await prisma.employee.create({
    data: { companyId, fullName: `${MARKER} xodim`, defaultOperationId: operation.id },
  });
  const category = await prisma.expenseCategory.create({
    data: { companyId, name: `${MARKER} ijara` },
  });

  // ── Данные периода ─────────────────────────────────────────────────────
  // 20 пар по 500 000 = 10 000 000 выручки, себестоимость 300 000 → 6 000 000
  await sales.create({
    paymentMethod: PaymentMethod.CASH,
    cashAccountId: account.id,
    discount: '0',
    soldAt: '2019-11-05T10:00:00.000Z',
    items: [{ productId: product.id, quantity: 20, unitPrice: '500000' }],
  });

  // Ещё одна продажа, которую потом сторнируем.
  const doomedSale = await sales.create({
    paymentMethod: PaymentMethod.CASH,
    cashAccountId: account.id,
    discount: '0',
    soldAt: '2019-11-06T10:00:00.000Z',
    items: [{ productId: product.id, quantity: 5, unitPrice: '500000' }],
  });

  await prisma.expense.create({
    data: {
      companyId,
      categoryId: category.id,
      amount: '1200000',
      spentAt: new Date('2019-11-10'),
      note: `${MARKER} ijara`,
    },
  });

  await payments.create({
    employeeId: employee.id,
    type: SalaryPaymentType.SALARY,
    amount: '2000000',
    paidAt: '2019-11-15',
    cashAccountId: account.id,
    note: `${MARKER} oylik`,
  });

  // Выработка: 30 пар подтверждено, 7 ждёт подтверждения.
  const rate = new Prisma.Decimal('12000');
  await prisma.workLog.create({
    data: {
      companyId,
      employeeId: employee.id,
      productId: product.id,
      operationId: operation.id,
      quantity: 30,
      rate,
      amount: rate.mul(30),
      workDate: new Date('2019-11-08'),
      status: WorkLogStatus.APPROVED,
      approvedAt: new Date(),
    },
  });
  await prisma.workLog.create({
    data: {
      companyId,
      employeeId: employee.id,
      productId: product.id,
      operationId: operation.id,
      quantity: 7,
      rate,
      amount: rate.mul(7),
      workDate: new Date('2019-11-09'),
      status: WorkLogStatus.PENDING,
    },
  });

  // ── До сторно ──────────────────────────────────────────────────────────
  console.log('\n=== Дашборд до сторно ===');
  const before = await analytics.dashboard({ period: 'month', dateFrom: FROM, dateTo: TO });

  check('выручка (25 пар)', before.revenue.value, '12500000');
  check('валовая прибыль', before.grossProfit.value, '5000000');
  check('расходы', before.expenses.value, '1200000');
  check('зарплата по выплатам', before.salaries.value, '2000000');
  check('чистая прибыль', before.netProfit.value, '1800000');
  check('продано пар', before.unitsSold, 25);
  check('произведено (только APPROVED)', before.unitsProduced, 30);

  /**
   * Инвариант, ради которого всё считается. Сходиться должны обе формулы:
   * себестоимость выводится из выручки и валовой прибыли, а чистая — из
   * валовой за вычетом расходов и выплат.
   */
  const cogs = Number(before.revenue.value) - Number(before.grossProfit.value);
  check('себестоимость проданного = 25 пар × 300 000', cogs, 7_500_000);
  check(
    'прибыль = валовая − расходы − выплаты',
    Number(before.netProfit.value),
    Number(before.grossProfit.value) - Number(before.expenses.value) - Number(before.salaries.value),
  );

  console.log('\n=== Бейджи ===');
  check('неподтверждённая выработка', before.alerts.pendingWorkLogs >= 1, true);

  console.log('\n=== Долг по зарплате ===');
  const period = await payroll.createPeriod({ periodStart: FROM, periodEnd: TO });
  const debt = await analytics.dashboard({ period: 'month', dateFrom: FROM, dateTo: TO });
  check(
    'начислено, но не выдано — отдельной строкой',
    Number(debt.salaryDebt) >= Number(period.entries[0]?.toPay ?? 0),
    true,
  );
  check('зарплата в прибыли осталась по выплатам', debt.salaries.value, '2000000');

  // ── После сторно ───────────────────────────────────────────────────────
  console.log('\n=== Сторно убирает продажу из всех цифр ===');
  await sales.cancel(doomedSale.id, 'test');

  const after = await analytics.dashboard({ period: 'month', dateFrom: FROM, dateTo: TO });
  check('выручка упала на сторнированное', after.revenue.value, '10000000');
  check('валовая прибыль пересчиталась', after.grossProfit.value, '4000000');
  check('продано пар', after.unitsSold, 20);
  check('чистая прибыль', after.netProfit.value, '800000');

  console.log('\n=== Топ товаров ===');
  const top = await analytics.topProducts({
    period: 'month',
    dateFrom: FROM,
    dateTo: TO,
    limit: 10,
    sort: 'revenue',
  });
  const mine = top.items.find((i) => i.name === `${MARKER} model`);
  check('модель в топе', mine?.unitsSold, 20);
  check('выручка по модели', mine?.revenue, '10000000');
  check('прибыль по модели', mine?.profit, '4000000');

  console.log('\n=== Выпуск ===');
  const byDay = await analytics.production({
    period: 'month',
    dateFrom: FROM,
    dateTo: TO,
    groupBy: 'day',
  });
  const day = byDay.items.find((i) => i.key === '2019-11-08');
  check('выпуск за день', day?.quantity, 30);
  check('неподтверждённое в выпуск не идёт', byDay.items.some((i) => i.key === '2019-11-09'), false);

  const byEmployee = await analytics.production({
    period: 'month',
    dateFrom: FROM,
    dateTo: TO,
    groupBy: 'employee',
  });
  const mineEmp = byEmployee.items.find((i) => i.label === `${MARKER} xodim`);
  check('выпуск по сотруднику', mineEmp?.quantity, 30);
  check('заработок по сотруднику', mineEmp?.amount, '360000');

  console.log('\n=== Прибыль с раскладкой ===');
  const profit = await analytics.profit({ period: 'month', dateFrom: FROM, dateTo: TO });
  check('себестоимость проданного', profit.cogs.value, '6000000');
  check('маржа посчитана', profit.margin !== null, true);

  console.log('\n=== Пустой период ===');
  const empty = await analytics.dashboard({
    period: 'month',
    dateFrom: '2015-01-01',
    dateTo: '2015-01-31',
  });
  check('выручка ноль, а не ошибка', empty.revenue.value, '0');
  check('динамика от нуля — прочерк', empty.revenue.changePercent, 'null');
  check('график пуст', empty.revenueChart.length, 0);

  await cleanup(companyId);

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

async function cleanup(companyId: string): Promise<void> {
  const products = await prisma.product.findMany({
    where: { sku: { startsWith: MARKER } },
    select: { id: true },
  });
  const productIds = products.map((p) => p.id);

  const saleIds = (
    await prisma.sale.findMany({
      where: { items: { some: { productId: { in: productIds } } } },
      select: { id: true },
    })
  ).map((s) => s.id);

  const employees = await prisma.employee.findMany({
    where: { fullName: { startsWith: MARKER } },
    select: { id: true },
  });
  const employeeIds = employees.map((e) => e.id);

  const accounts = await prisma.cashAccount.findMany({
    where: { name: { startsWith: MARKER } },
    select: { id: true },
  });
  const accountIds = accounts.map((a) => a.id);

  if (saleIds.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.saleItem.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.sale.deleteMany({ where: { id: { in: saleIds } } });
  }

  if (employeeIds.length > 0) {
    await prisma.salaryPayment.deleteMany({ where: { employeeId: { in: employeeIds } } });
    await prisma.workLog.deleteMany({ where: { employeeId: { in: employeeIds } } });
    await prisma.payrollEntry.deleteMany({ where: { employeeId: { in: employeeIds } } });
  }

  await prisma.payrollPeriod.deleteMany({
    where: { companyId, periodStart: new Date(FROM) },
  });
  await prisma.expense.updateMany({
    where: { category: { name: { startsWith: MARKER } } },
    data: { cashTransactionId: null },
  });
  await prisma.expense.deleteMany({ where: { category: { name: { startsWith: MARKER } } } });
  await prisma.expenseCategory.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
  await prisma.stockMovement.deleteMany({ where: { productId: { in: productIds } } });
  await prisma.product.deleteMany({ where: { id: { in: productIds } } });
  await prisma.employee.deleteMany({ where: { id: { in: employeeIds } } });
  await prisma.pieceRate.deleteMany({ where: { operation: { name: { startsWith: MARKER } } } });
  await prisma.operation.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });

  if (accountIds.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { accountId: { in: accountIds } } });
    await prisma.cashAccount.deleteMany({ where: { id: { in: accountIds } } });
  }
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
