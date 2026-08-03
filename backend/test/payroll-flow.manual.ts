/**
 * Полный сценарий зарплаты на живой БД: от выработки до денег в кассе.
 *
 * Проверяются инварианты, которые не поймать модульным тестом, потому что
 * они живут в транзакциях и ограничениях базы: идемпотентность пересчёта,
 * захват выработки при закрытии периода, согласованность кассы и ведомости.
 *
 * Скрипт заводит собственные данные (сотрудник, модель, операция, касса)
 * в далёком прошлом, чтобы не пересечься с демо-данными, и убирает их
 * за собой — прогонять можно сколько угодно раз подряд.
 *
 * Запуск (нужна БД с демо-данными):
 *   npm run test:payroll
 */
import { Prisma, SalaryPaymentType, WorkLogStatus } from '@prisma/client';
import { CashService } from '../src/modules/cash/cash.service';
import { PayrollService } from '../src/modules/payroll/payroll.service';
import { SalaryPaymentsService } from '../src/modules/payroll/salary-payments.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const cash = new CashService(prisma);
const payroll = new PayrollService(prisma);
const payments = new SalaryPaymentsService(prisma, payroll, cash);

/** Период 2019 года — заведомо вне демо-данных и вне реальной работы цеха. */
const PERIOD_START = '2019-03-01';
const PERIOD_END = '2019-03-31';

const MARKER = 'PAYROLL-TEST';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

function checkThrows(label: string, code: string, fn: () => Promise<unknown>): Promise<void> {
  return fn().then(
    () => {
      failed++;
      console.log(`  ❌ ${label}: ошибки не было, ожидался ${code}`);
    },
    (error: unknown) => {
      const actual = (error as { code?: string }).code ?? String(error);
      const ok = actual === code;
      if (ok) passed++;
      else failed++;
      console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}`);
    },
  );
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

  // ── Подготовка ─────────────────────────────────────────────────────────
  const operation = await prisma.operation.create({
    data: { companyId, name: `${MARKER} operatsiya`, sortOrder: 999 },
  });

  const product = await prisma.product.create({
    data: { companyId, sku: `${MARKER}-SKU`, name: `${MARKER} model`, salePrice: '100000' },
  });

  const employee = await prisma.employee.create({
    data: { companyId, fullName: `${MARKER} xodim`, defaultOperationId: operation.id },
  });

  const account = await prisma.cashAccount.create({
    data: { companyId, name: `${MARKER} kassa`, balance: '10000000' },
  });

  // 3 дня по 10 пар при ставке 12 000 = 360 000
  const rate = new Prisma.Decimal('12000');
  for (const day of ['2019-03-05', '2019-03-06', '2019-03-07']) {
    await prisma.workLog.create({
      data: {
        companyId,
        employeeId: employee.id,
        productId: product.id,
        operationId: operation.id,
        quantity: 10,
        rate,
        amount: rate.mul(10),
        workDate: new Date(day),
        status: WorkLogStatus.APPROVED,
        approvedAt: new Date(),
      },
    });
  }

  // Запись вне периода — не должна попасть в начисление.
  await prisma.workLog.create({
    data: {
      companyId,
      employeeId: employee.id,
      productId: product.id,
      operationId: operation.id,
      quantity: 5,
      rate,
      amount: rate.mul(5),
      workDate: new Date('2019-04-02'),
      status: WorkLogStatus.APPROVED,
      approvedAt: new Date(),
    },
  });

  // Неподтверждённая запись внутри периода — тоже не должна попасть.
  await prisma.workLog.create({
    data: {
      companyId,
      employeeId: employee.id,
      productId: product.id,
      operationId: operation.id,
      quantity: 7,
      rate,
      amount: rate.mul(7),
      workDate: new Date('2019-03-10'),
      status: WorkLogStatus.PENDING,
    },
  });

  // ── Предпросмотр ───────────────────────────────────────────────────────
  console.log('\n=== Предпросмотр до создания периода ===');
  const preview = await payroll.preview({ dateFrom: PERIOD_START, dateTo: PERIOD_END });
  check('начислится за период', preview.totalAmount, '360000');
  check('периодов при этом не создано', await prisma.payrollPeriod.count(), 0);

  // ── Открытие и расчёт ──────────────────────────────────────────────────
  console.log('\n=== Открытие периода ===');
  const period = await payroll.createPeriod({
    periodStart: PERIOD_START,
    periodEnd: PERIOD_END,
  });
  check('статус', period.status, 'OPEN');
  check('сотрудников в ведомости', period.entries.length, 1);
  check('выработка за период', period.entries[0].workAmount, '360000');
  check('только APPROVED и только внутри периода', period.entries[0].totalAccrued, '360000');
  check('к выплате', period.entries[0].toPay, '360000');

  const entryId = period.entries[0].id;

  console.log('\n=== Пересчёт идемпотентен ===');
  const again = await payroll.calculate(period.periodId);
  check('сумма не изменилась', again.entries[0].workAmount, '360000');
  check('начислений не задвоилось', again.entries.length, 1);

  console.log('\n=== Пересечение периодов запрещено ===');
  await checkThrows('период внутри существующего', 'PERIOD_OVERLAP', () =>
    payroll.createPeriod({ periodStart: '2019-03-10', periodEnd: '2019-03-20' }),
  );

  // ── Премия ─────────────────────────────────────────────────────────────
  console.log('\n=== Премия и удержание ===');
  const withBonus = await payroll.updateEntry(entryId, { bonus: '40000', deduction: '10000' });
  check('начислено с премией', withBonus.entries[0].totalAccrued, '390000');
  check('итог периода обновлён', withBonus.totalAmount, '390000');

  // ── Аванс ──────────────────────────────────────────────────────────────
  console.log('\n=== Выплата аванса ===');
  const balanceBefore = (await prisma.cashAccount.findFirstOrThrow({ where: { id: account.id } }))
    .balance;

  // userId не передаём: скрипт работает без HTTP-запроса, автора выплаты нет.
  await payments.create({
    employeeId: employee.id,
    type: SalaryPaymentType.ADVANCE,
    amount: '150000',
    paidAt: '2019-03-15',
    cashAccountId: account.id,
  });

  const afterAdvance = await payroll.findOnePeriod(period.periodId);
  check('аванс учтён в начислении', afterAdvance.entries[0].advancePaid, '150000');
  check('к выплате уменьшилось', afterAdvance.entries[0].toPay, '240000');
  check('начислено не изменилось', afterAdvance.entries[0].totalAccrued, '390000');

  const balanceAfter = (await prisma.cashAccount.findFirstOrThrow({ where: { id: account.id } }))
    .balance;
  check('деньги ушли из кассы', balanceBefore.minus(balanceAfter).toString(), '150000');

  const cashTx = await prisma.cashTransaction.findFirst({
    where: { refType: 'salary_payment' },
    orderBy: { createdAt: 'desc' },
  });
  check('движение по кассе создано', cashTx?.direction, 'OUT');
  check('категория движения', cashTx?.category, 'SALARY');

  console.log('\n=== Пересчёт после аванса не ломает суммы ===');
  const recalculated = await payroll.calculate(period.periodId);
  check('аванс не задвоился', recalculated.entries[0].advancePaid, '150000');
  check('к выплате прежнее', recalculated.entries[0].toPay, '240000');

  // ── Закрытие ───────────────────────────────────────────────────────────
  console.log('\n=== Закрытие периода ===');
  const closed = await payroll.close(period.periodId);
  check('статус', closed.status, 'CLOSED');

  const claimed = await prisma.workLog.count({
    where: { payrollEntryId: entryId },
  });
  check('выработка захвачена периодом', claimed, 3);

  const unclaimedInside = await prisma.workLog.count({
    where: {
      workDate: { gte: new Date(PERIOD_START), lte: new Date(PERIOD_END) },
      status: WorkLogStatus.APPROVED,
      payrollEntryId: null,
    },
  });
  check('незахваченных APPROVED внутри периода не осталось', unclaimedInside, 0);

  console.log('\n=== Закрытый период неприкосновенен ===');
  await checkThrows('повторное закрытие', 'PERIOD_ALREADY_CLOSED', () =>
    payroll.close(period.periodId),
  );
  await checkThrows('пересчёт закрытого', 'PERIOD_ALREADY_CLOSED', () =>
    payroll.calculate(period.periodId),
  );
  await checkThrows('правка начисления в закрытом', 'PERIOD_ALREADY_CLOSED', () =>
    payroll.updateEntry(entryId, { bonus: '999999' }),
  );

  console.log('\n=== Двойная оплата невозможна ===');
  const previewAfterClose = await payroll.preview({
    dateFrom: PERIOD_START,
    dateTo: PERIOD_END,
  });
  check('та же выработка второй раз не начислится', previewAfterClose.totalAmount, '0');

  await cleanup(companyId);

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

/** Полная уборка за собой — скрипт должен быть перезапускаемым. */
async function cleanup(companyId: string): Promise<void> {
  const employees = await prisma.employee.findMany({
    where: { fullName: { startsWith: MARKER } },
    select: { id: true },
  });
  const ids = employees.map((e) => e.id);

  if (ids.length > 0) {
    // Порядок обязателен: выплата ссылается на движение по кассе,
    // выработка — на начисление. Иначе внешние ключи не дадут удалить.
    await prisma.salaryPayment.deleteMany({ where: { employeeId: { in: ids } } });
    await prisma.workLog.deleteMany({ where: { employeeId: { in: ids } } });
    await prisma.payrollEntry.deleteMany({ where: { employeeId: { in: ids } } });
  }

  await prisma.cashTransaction.deleteMany({
    where: { companyId, note: { startsWith: 'Avans — ' + MARKER } },
  });
  await prisma.payrollPeriod.deleteMany({
    where: { companyId, periodStart: new Date(PERIOD_START) },
  });
  await prisma.pieceRate.deleteMany({
    where: { operation: { name: { startsWith: MARKER } } },
  });
  await prisma.employee.deleteMany({ where: { id: { in: ids } } });
  await prisma.product.deleteMany({ where: { companyId, sku: { startsWith: MARKER } } });
  await prisma.operation.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
  await prisma.cashAccount.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
