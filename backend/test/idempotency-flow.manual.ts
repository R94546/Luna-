/**
 * Идемпотентность денежных операций — по-настоящему, через HTTP.
 *
 * Модульным тестом это не подтвердить: защита живёт в интерцепторе, а он
 * видит заголовки, тело запроса и код ответа. Поэтому здесь поднимается
 * настоящее приложение на свободном порту и опрашивается настоящими
 * запросами — включая два одновременных нажатия «Сохранить».
 *
 * Запуск:
 *   npm run test:idempotency
 */
process.env.TELEGRAM_BOT_TOKEN = ''; // бот в этом сценарии не нужен

import { INestApplication } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { randomUUID } from 'node:crypto';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

const PORT = 3199;
const API = `http://localhost:${PORT}/api/v1`;
const MARKER = 'IDEMP-TEST';

let passed = 0;
let failed = 0;
let token = '';

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

interface Reply {
  status: number;
  body: Record<string, unknown>;
  replay: boolean;
}

async function post(path: string, body: unknown, key?: string): Promise<Reply> {
  const response = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...(key ? { 'Idempotency-Key': key } : {}),
    },
    body: JSON.stringify(body),
  });

  return {
    status: response.status,
    body: (await response.json()) as Record<string, unknown>,
    replay: response.headers.get('idempotent-replay') === 'true',
  };
}

async function main(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: ['error'] });
  app.setGlobalPrefix('api/v1');
  await app.listen(PORT);

  const prisma = app.get(PrismaService);

  try {
    await scenario(app, prisma);
  } finally {
    await cleanup(prisma);
    await app.close();
  }

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

async function scenario(app: INestApplication, prisma: PrismaService): Promise<void> {
  const login = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: '901234567', password: 'luna12345' }),
  });
  const auth = (await login.json()) as { accessToken?: string };
  if (!auth.accessToken) throw new Error('Вход не удался — выполните `npm run seed`.');
  token = auth.accessToken;

  await cleanup(prisma);

  const account = (
    await post('/cash/accounts', { name: `${MARKER} kassa`, type: 'CASH', balance: '1000000' })
  ).body as { id: string };

  const payload = {
    accountId: account.id,
    direction: 'IN',
    category: 'INVESTMENT',
    amount: '250000',
    occurredAt: '2019-09-01',
    note: `${MARKER} vznos`,
  };

  // ── Повтор возвращает первый результат ─────────────────────────────────
  console.log('\n=== Повтор с тем же ключом ===');
  const key = randomUUID();

  const first = await post('/cash/transactions', payload, key);
  check('первый запрос', first.status, 201);
  check('пометки повтора нет', first.replay, false);

  const second = await post('/cash/transactions', payload, key);
  check('повтор', second.status, 201);
  check('тот же id, а не новая запись', second.body.id, first.body.id);
  check('заголовок Idempotent-Replay', second.replay, true);

  const created = await prisma.cashTransaction.count({ where: { note: `${MARKER} vznos` } });
  check('движений в кассе создано', created, 1);

  const balance = await prisma.cashAccount.findFirstOrThrow({ where: { id: account.id } });
  check('баланс сдвинулся один раз', balance.balance.toString(), '1250000');

  // ── Тот же ключ, другое тело ───────────────────────────────────────────
  console.log('\n=== Тот же ключ с другими данными ===');
  const tampered = await post('/cash/transactions', { ...payload, amount: '999999' }, key);
  check('отклонено', tampered.status, 409);
  check('код ошибки', tampered.body.code, 'IDEMPOTENCY_KEY_REUSED');

  const stillOne = await prisma.cashTransaction.count({ where: { note: `${MARKER} vznos` } });
  check('вторая запись не появилась', stillOne, 1);

  // ── Порядок полей не считается изменением ──────────────────────────────
  console.log('\n=== Порядок полей в теле ===');
  const reordered = await post(
    '/cash/transactions',
    {
      note: payload.note,
      occurredAt: payload.occurredAt,
      amount: payload.amount,
      category: payload.category,
      direction: payload.direction,
      accountId: payload.accountId,
    },
    key,
  );
  check('распознан как повтор', reordered.body.id, first.body.id);

  // ── Без заголовка защиты нет ───────────────────────────────────────────
  console.log('\n=== Без заголовка работает как раньше ===');
  const bare1 = await post('/cash/transactions', { ...payload, note: `${MARKER} bez` });
  const bare2 = await post('/cash/transactions', { ...payload, note: `${MARKER} bez` });
  check('созданы две разные записи', bare1.body.id !== bare2.body.id, true);
  check('записей в базе', await prisma.cashTransaction.count({ where: { note: `${MARKER} bez` } }), 2);

  // ── Два одновременных нажатия ──────────────────────────────────────────
  console.log('\n=== Двойное нажатие одновременно ===');
  const raceKey = randomUUID();
  const racePayload = { ...payload, note: `${MARKER} race` };

  const [a, b] = await Promise.all([
    post('/cash/transactions', racePayload, raceKey),
    post('/cash/transactions', racePayload, raceKey),
  ]);

  /**
   * Исход гонки зависит от того, успел ли первый запрос дописать результат:
   * второй получит либо готовый ответ (201, тот же id), либо «выполняется»
   * (409). Оба поведения правильные, и требовать конкретного значит писать
   * тест, который падает от нагрузки на машине.
   *
   * Проверяется инвариант, ради которого всё и делалось: денег списалось
   * ровно один раз.
   */
  check('движение создано одно', await prisma.cashTransaction.count({ where: { note: `${MARKER} race` } }), 1);

  const outcomes = [a, b].map((r) => (r.status === 201 ? String(r.body.id) : String(r.body.code)));
  const succeeded = [a, b].filter((r) => r.status === 201);

  check(
    'исход допустимый',
    succeeded.every((r) => r.body.id === succeeded[0].body.id) &&
      [a, b].every(
        (r) =>
          r.status === 201 ||
          (r.status === 409 &&
            ['IDEMPOTENCY_IN_PROGRESS', 'IDEMPOTENCY_KEY_REUSED'].includes(String(r.body.code))),
      ),
    true,
  );
  console.log(`     (что вернулось: ${outcomes.join(' и ')})`);

  // ── Расходы защищены тем же механизмом ─────────────────────────────────
  console.log('\n=== Расход не задваивается ===');
  const category = (await post('/expense-categories', { name: `${MARKER} kategoriya` })).body as {
    id: string;
  };

  const expenseKey = randomUUID();
  const expensePayload = {
    categoryId: category.id,
    amount: '70000',
    spentAt: '2019-09-02',
    cashAccountId: account.id,
    note: `${MARKER} rasxod`,
  };

  const e1 = await post('/expenses', expensePayload, expenseKey);
  const e2 = await post('/expenses', expensePayload, expenseKey);
  check('тот же расход', e2.body.id, e1.body.id);
  check('расходов в базе', await prisma.expense.count({ where: { note: `${MARKER} rasxod` } }), 1);

  // ── Ошибка освобождает ключ ────────────────────────────────────────────
  console.log('\n=== После ошибки ключ свободен ===');
  const retryKey = randomUUID();

  const broken = await post(
    '/expenses',
    { ...expensePayload, cashAccountId: '00000000-0000-0000-0000-000000000000' },
    retryKey,
  );
  check('первая попытка не прошла', broken.status, 404);

  const fixed = await post('/expenses', { ...expensePayload, note: `${MARKER} povtor` }, retryKey);
  check('исправленная попытка прошла', fixed.status, 201);
}

async function cleanup(prisma: PrismaService): Promise<void> {
  const accounts = await prisma.cashAccount.findMany({
    where: { name: { startsWith: MARKER } },
    select: { id: true },
  });
  const ids = accounts.map((a) => a.id);

  await prisma.expense.updateMany({
    where: { note: { startsWith: MARKER } },
    data: { cashTransactionId: null },
  });
  await prisma.expense.deleteMany({ where: { category: { name: { startsWith: MARKER } } } });
  await prisma.expenseCategory.deleteMany({ where: { name: { startsWith: MARKER } } });

  if (ids.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { accountId: { in: ids } } });
    await prisma.cashAccount.deleteMany({ where: { id: { in: ids } } });
  }

  await prisma.idempotencyKey.deleteMany({ where: { endpoint: { contains: 'cash' } } });
  await prisma.idempotencyKey.deleteMany({ where: { endpoint: { contains: 'expenses' } } });
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
