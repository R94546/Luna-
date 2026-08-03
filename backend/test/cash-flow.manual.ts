/**
 * Касса и расходы на живой БД.
 *
 * Главный инвариант модуля: баланс кассы всегда равен сумме её движений.
 * Разойтись они могут только там, где кто-то тронул `balance` мимо общего
 * механизма, и поймать это можно лишь на настоящей базе с настоящими
 * транзакциями — здесь и проверяется.
 *
 * Скрипт заводит свою кассу и категорию расходов, убирает их за собой
 * и не трогает демо-данные.
 *
 * Запуск:
 *   npm run test:cash
 */
import { CashCategory, CashDirection, Prisma } from '@prisma/client';
import { CashService } from '../src/modules/cash/cash.service';
import { ExpensesService } from '../src/modules/expenses/expenses.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const cash = new CashService(prisma);
const expenses = new ExpensesService(prisma, cash);

const MARKER = 'CASH-TEST';
const DATE_FROM = '2019-06-01';
const DATE_TO = '2019-06-30';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

async function checkThrows(label: string, code: string, fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn();
    failed++;
    console.log(`  ❌ ${label}: ошибки не было, ожидался ${code}`);
  } catch (error) {
    const actual = (error as { code?: string }).code ?? String(error);
    const ok = actual === code;
    if (ok) passed++;
    else failed++;
    console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}`);
  }
}

/** Баланс, посчитанный из журнала, — эталон, с которым сверяется денормализация. */
async function balanceFromJournal(accountId: string): Promise<Prisma.Decimal> {
  const rows = await prisma.cashTransaction.groupBy({
    by: ['direction'],
    where: { accountId },
    _sum: { amount: true },
  });

  const of = (d: CashDirection) =>
    rows.find((r) => r.direction === d)?._sum.amount ?? new Prisma.Decimal(0);

  return of(CashDirection.IN).minus(of(CashDirection.OUT));
}

async function storedBalance(accountId: string): Promise<Prisma.Decimal> {
  const account = await prisma.cashAccount.findFirstOrThrow({ where: { id: accountId } });
  return account.balance;
}

async function checkConsistent(label: string, accountId: string): Promise<void> {
  const stored = await storedBalance(accountId);
  const journal = await balanceFromJournal(accountId);
  check(`${label} (баланс = журнал)`, stored.toString(), journal.toString());
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

  // ── Касса со стартовым остатком ────────────────────────────────────────
  console.log('\n=== Заведение кассы ===');
  const account = await cash.createAccount({
    name: `${MARKER} kassa`,
    type: 'CASH',
    balance: '5000000',
    isDefault: false,
  });
  check('стартовый остаток', account.balance, '5000000');
  await checkConsistent('после заведения', account.id);

  const openingTx = await prisma.cashTransaction.findFirst({
    where: { accountId: account.id },
  });
  check('остаток проведён через журнал', openingTx?.category, 'INVESTMENT');

  await checkThrows('касса с тем же именем', 'DUPLICATE', () =>
    cash.createAccount({ name: `${MARKER} kassa`, type: 'CASH', isDefault: false }),
  );

  // ── Ручные операции ────────────────────────────────────────────────────
  console.log('\n=== Ручные операции ===');
  await cash.createTransaction({
    accountId: account.id,
    direction: CashDirection.IN,
    category: CashCategory.INVESTMENT,
    amount: '1000000',
    occurredAt: '2019-06-05',
    note: `${MARKER} vnesenie`,
  });
  check('после внесения', (await storedBalance(account.id)).toString(), '6000000');

  await cash.createTransaction({
    accountId: account.id,
    direction: CashDirection.OUT,
    category: CashCategory.WITHDRAWAL,
    amount: '500000',
    occurredAt: '2019-06-06',
    note: `${MARKER} izyatie`,
  });
  check('после изъятия', (await storedBalance(account.id)).toString(), '5500000');
  await checkConsistent('после ручных операций', account.id);

  // ── Расходы ────────────────────────────────────────────────────────────
  console.log('\n=== Расходы ===');
  const category = await expenses.createCategory({ name: `${MARKER} ijara` });

  const expense = await expenses.create({
    categoryId: category.id,
    amount: '800000',
    spentAt: '2019-06-10',
    cashAccountId: account.id,
    note: `${MARKER} ijara iyun`,
  });
  check('расход списал деньги', (await storedBalance(account.id)).toString(), '4700000');
  check('касса привязана к расходу', expense.cashAccountId, account.id);
  await checkConsistent('после расхода', account.id);

  const expenseTx = await prisma.cashTransaction.findFirst({
    where: { refType: 'expense', refId: expense.id },
  });
  check('движение по расходу', expenseTx?.category, 'EXPENSE');
  check('направление', expenseTx?.direction, 'OUT');

  console.log('\n=== Правка расхода ===');
  await expenses.update(expense.id, { amount: '950000' });
  check('баланс сдвинулся на разницу', (await storedBalance(account.id)).toString(), '4550000');
  await checkConsistent('после правки суммы', account.id);

  const updatedTx = await prisma.cashTransaction.findFirstOrThrow({
    where: { refType: 'expense', refId: expense.id },
  });
  check('сумма движения обновилась', updatedTx.amount.toString(), '950000');

  await expenses.update(expense.id, { amount: '950000' });
  check('правка тем же значением ничего не сдвинула', (await storedBalance(account.id)).toString(), '4550000');

  // ── Сводка ─────────────────────────────────────────────────────────────
  console.log('\n=== Сводка за период ===');
  const summary = await cash.summary({ dateFrom: DATE_FROM, dateTo: DATE_TO });
  const mine = summary.accounts.find((a) => a.id === account.id);
  check('касса в сводке', mine?.balance, '4550000');

  const expenseRow = summary.outcome.byCategory.find((r) => r.name === `${MARKER} ijara`);
  check('расход раскрыт по своей категории', expenseRow?.amount, '950000');

  const withdrawalRow = summary.outcome.byCategory.find((r) => r.category === 'WITHDRAWAL');
  check('изъятие отдельной строкой', withdrawalRow?.amount, '500000');

  // ── Запрет на ручную зарплату ──────────────────────────────────────────
  console.log('\n=== Зарплату вручную в кассу не записать ===');
  const { createTransactionSchema } = await import('../src/modules/cash/dto/cash.dto');
  const salaryAttempt = createTransactionSchema.safeParse({
    accountId: account.id,
    direction: 'OUT',
    category: 'SALARY',
    amount: '100000',
    occurredAt: '2019-06-15',
  });
  check('категория SALARY отклонена', salaryAttempt.success, false);

  const saleAttempt = createTransactionSchema.safeParse({
    accountId: account.id,
    direction: 'IN',
    category: 'SALE',
    amount: '100000',
    occurredAt: '2019-06-15',
  });
  check('категория SALE отклонена', saleAttempt.success, false);

  // ── Удаление расхода ───────────────────────────────────────────────────
  console.log('\n=== Удаление расхода сторнирует кассу ===');
  await expenses.remove(expense.id);
  check('деньги вернулись', (await storedBalance(account.id)).toString(), '5500000');
  await checkConsistent('после удаления', account.id);

  const orphanTx = await prisma.cashTransaction.count({
    where: { refType: 'expense', refId: expense.id },
  });
  check('движение удалено вместе с расходом', orphanTx, 0);

  await cleanup(companyId);

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

async function cleanup(companyId: string): Promise<void> {
  const accounts = await prisma.cashAccount.findMany({
    where: { name: { startsWith: MARKER } },
    select: { id: true },
  });
  const accountIds = accounts.map((a) => a.id);

  if (accountIds.length > 0) {
    // Расход ссылается на движение — сначала снимаем ссылку, потом удаляем.
    await prisma.expense.updateMany({
      where: { cashTransaction: { accountId: { in: accountIds } } },
      data: { cashTransactionId: null },
    });
    await prisma.expense.deleteMany({ where: { category: { name: { startsWith: MARKER } } } });
    await prisma.cashTransaction.deleteMany({ where: { accountId: { in: accountIds } } });
  }

  await prisma.expenseCategory.deleteMany({
    where: { companyId, name: { startsWith: MARKER } },
  });
  await prisma.cashAccount.deleteMany({ where: { id: { in: accountIds } } });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
