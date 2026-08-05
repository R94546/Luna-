/**
 * Отчёты и уведомления через настоящий HTTP.
 *
 * Сценарий `test:reports` дёргает сервисы напрямую и потому не видит
 * всего, что стоит перед ними: маршруты, проверку роли, разбор тела,
 * коды ответов и заголовки отдачи файла. Ошибка в любом из них означает,
 * что кнопка в приложении не работает, — а сервис при этом исправен.
 *
 * Поднимает приложение на своём порту, чтобы не мешать `npm run start:dev`.
 *
 * Запуск:
 *   npm run test:reports:http
 */
process.env.TELEGRAM_BOT_TOKEN = ''; // бот в этом сценарии не нужен

import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/prisma/prisma.service';

const PORT = 3198;
const API = `http://localhost:${PORT}/api/v1`;

let passed = 0;
let failed = 0;
let token = '';

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

/// Своя форма запроса вместо `RequestInit`: тип глобальный, но линтеру
/// в конфиге Node он неизвестен, а нужны здесь три поля.
interface Request {
  method?: string;
  body?: string;
  headers?: Record<string, string>;
}

function authorized(init: Request = {}): Request {
  return {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  };
}

async function main(): Promise<void> {
  const app = await NestFactory.create(AppModule, { logger: ['error'] });
  app.setGlobalPrefix('api/v1');
  await app.listen(PORT);

  const prisma = app.get(PrismaService);

  try {
    await scenario(prisma);
  } finally {
    await app.close();
  }

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

async function scenario(prisma: PrismaService): Promise<void> {
  const login = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: '901234567', password: 'luna12345' }),
  });
  const auth = (await login.json()) as { accessToken?: string };
  if (!auth.accessToken) throw new Error('Вход не удался — выполните `npm run seed`.');
  token = auth.accessToken;

  // ── Постановка в очередь ────────────────────────────────────────────────
  console.log('\n=== POST /reports/export ===');

  const started = await fetch(
    `${API}/reports/export`,
    authorized({
      method: 'POST',
      body: JSON.stringify({
        type: 'SALES',
        format: 'XLSX',
        dateFrom: '2026-07-01',
        dateTo: '2026-08-31',
      }),
    }),
  );

  const job = (await started.json()) as { jobId?: string; status?: string; url?: string };

  // 202, а не 200: файла ещё нет, и клиент обязан это различать.
  check('код ответа', started.status, 202);
  check('статус', job.status, 'PENDING');
  ok('выдан jobId', typeof job.jobId === 'string', job.jobId ?? '—');
  ok('ссылки пока нет', job.url === undefined);

  // ── Ожидание готовности ─────────────────────────────────────────────────
  console.log('\n=== GET /reports/:jobId ===');

  let ready: { status?: string; url?: string; fileName?: string } = {};

  for (let attempt = 0; attempt < 40; attempt++) {
    const response = await fetch(`${API}/reports/${job.jobId}`, authorized());
    ready = (await response.json()) as typeof ready;
    if (ready.status !== 'PENDING') break;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  check('статус', ready.status, 'READY');
  check('ссылка на скачивание', ready.url, `/reports/${job.jobId}/download`);

  // ── Отдача файла ────────────────────────────────────────────────────────
  console.log('\n=== GET /reports/:jobId/download ===');

  const file = await fetch(`${API}/reports/${job.jobId}/download`, authorized());
  const bytes = Buffer.from(await file.arrayBuffer());

  check('код ответа', file.status, 200);
  ok(
    'тип содержимого — таблица',
    (file.headers.get('content-type') ?? '').includes('spreadsheetml'),
    file.headers.get('content-type') ?? '—',
  );
  ok(
    'файл предлагается скачать',
    (file.headers.get('content-disposition') ?? '').includes(ready.fileName ?? '?'),
    file.headers.get('content-disposition') ?? '—',
  );
  // XLSX — это zip, и начинается он с «PK». Проверка ловит случай, когда
  // вместо файла прилетела страница ошибки с кодом 200.
  ok('это настоящий xlsx', bytes.subarray(0, 2).toString() === 'PK', `${bytes.length} байт`);

  // ── Чего быть не должно ─────────────────────────────────────────────────
  console.log('\n=== Отказы ===');

  const anonymous = await fetch(`${API}/reports/${job.jobId}`);
  check('без токена', anonymous.status, 401);

  const stranger = await fetch(
    `${API}/reports/00000000-0000-0000-0000-000000000000`,
    authorized(),
  );
  // 404, а не 403: по коду ответа нельзя перебором узнать чужие jobId.
  check('чужой отчёт', stranger.status, 404);

  const broken = await fetch(
    `${API}/reports/export`,
    authorized({
      method: 'POST',
      body: JSON.stringify({
        type: 'SALES',
        format: 'XLSX',
        dateFrom: '2026-08-31',
        dateTo: '2026-07-01',
      }),
    }),
  );
  const brokenBody = (await broken.json()) as {
    message?: string;
    details?: { fields?: Record<string, string> };
  };
  check('конец периода раньше начала', broken.status, 400);
  ok(
    'сообщение переведено, а не ключ',
    !(brokenBody.message ?? '').includes('validation.'),
    brokenBody.message ?? '—',
  );
  // Общего «проверьте поля» мало: форма подсвечивает конкретную дату,
  // и текст для неё должен приехать с сервера переведённым.
  ok(
    'поле с ошибкой названо',
    typeof brokenBody.details?.fields?.dateTo === 'string' &&
      !brokenBody.details.fields.dateTo.includes('validation.'),
    brokenBody.details?.fields?.dateTo ?? '—',
  );

  // ── Уведомления ─────────────────────────────────────────────────────────
  console.log('\n=== Уведомления ===');

  const company = await prisma.company.findFirstOrThrow({ where: { slug: 'luna-shoes' } });
  const created = await prisma.notification.create({
    data: {
      companyId: company.id,
      type: 'SYSTEM',
      title: 'HTTP-проверка',
      body: 'Уведомление из сценария',
    },
  });

  const list = await fetch(`${API}/notifications`, authorized());
  const page = (await list.json()) as {
    items?: { id: string }[];
    unread?: number;
  };

  check('код ответа', list.status, 200);
  ok(
    'уведомление в ленте',
    (page.items ?? []).some((item) => item.id === created.id),
    `${page.items?.length ?? 0} шт`,
  );
  ok('счётчик непрочитанных', (page.unread ?? 0) > 0, `${page.unread}`);

  const read = await fetch(
    `${API}/notifications/${created.id}/read`,
    authorized({ method: 'POST' }),
  );
  check('отметка прочитанным', read.status, 200);

  const all = await fetch(`${API}/notifications/read-all`, authorized({ method: 'POST' }));
  check('«прочитать все»', all.status, 200);

  // Маршрут объявлен после read-all — если порядок в контроллере
  // перепутать, Nest примет «read-all» за :id и вернёт 400.
  const afterAll = await fetch(`${API}/notifications?unreadOnly=true`, authorized());
  const rest = (await afterAll.json()) as { items?: unknown[] };
  check('непрочитанных не осталось', rest.items?.length, 0);

  const device = await fetch(
    `${API}/devices/push-token`,
    authorized({
      method: 'POST',
      body: JSON.stringify({ token: 'http-test-token-0001', platform: 'android' }),
    }),
  );
  check('регистрация устройства', device.status, 200);

  await prisma.notification.delete({ where: { id: created.id } });
  await prisma.pushToken.deleteMany({ where: { token: 'http-test-token-0001' } });
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
