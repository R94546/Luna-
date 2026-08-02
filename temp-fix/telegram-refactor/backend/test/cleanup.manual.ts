/**
 * Проверка уборки in-memory хранилищ Telegram-модуля.
 *
 * Интервалы вызываются напрямую: ждать реальные 5 и 10 минут в тесте
 * бессмысленно, а проверить надо именно логику удаления протухших записей.
 */
import { ConfigService } from '@nestjs/config';
import { StartHandler } from '../src/modules/telegram/handlers/start.handler';
import { ReportHandler } from '../src/modules/telegram/handlers/report.handler';
import { SummaryHandler } from '../src/modules/telegram/handlers/summary.handler';
import { TelegramSessionService } from '../src/modules/telegram/telegram-session.service';
import { TelegramService } from '../src/modules/telegram/telegram.service';
import { WorkLogsService } from '../src/modules/work-logs/work-logs.service';
import { PieceRatesService } from '../src/modules/piece-rates/piece-rates.service';
import { PrismaService } from '../src/prisma/prisma.service';

/* eslint-disable @typescript-eslint/no-explicit-any */
const prisma = new PrismaService();
const rates = new PieceRatesService(prisma);
const workLogs = new WorkLogsService(prisma, rates);
const sessions = new TelegramSessionService();
const service = new TelegramService(
  prisma,
  new ConfigService({}),
  new StartHandler(prisma),
  new ReportHandler(prisma, workLogs, sessions),
  new SummaryHandler(workLogs),
);

console.log('=== rateLimits ===');
const limits = (service as any).rateLimits as Map<number, { count: number; resetAt: number }>;

for (let i = 0; i < 1000; i++) (service as any).checkRateLimit(i);
console.log(`  после 1000 отправителей: ${limits.size}`);

service.cleanupRateLimits();
console.log(`  сразу после уборки (окно ещё живо): ${limits.size} — записи не тронуты ✅`);

// Протухаем половину: сдвигаем окно в прошлое
let n = 0;
for (const [k, v] of limits) {
  if (n++ % 2 === 0) v.resetAt = Date.now() - 1;
}
service.cleanupRateLimits();
console.log(`  после протухания половины: ${limits.size} ${limits.size === 500 ? '✅' : '❌'}`);

console.log('');
console.log('=== sessions ===');
for (let i = 0; i < 1000; i++) sessions.get(i);
console.log(`  после 1000 диалогов: ${sessions.size}`);

sessions.cleanupExpired();
console.log(`  сразу после уборки (TTL не истёк): ${sessions.size} — живые сохранены ✅`);

// Протухаем 600 сессий
n = 0;
for (let i = 0; i < 600; i++) {
  const s = sessions.get(i);
  s.updatedAt = Date.now() - 31 * 60_000;
}
sessions.cleanupExpired();
console.log(`  после протухания 600: ${sessions.size} ${sessions.size === 400 ? '✅' : '❌'}`);

console.log('');
console.log('=== маскирование tgId ===');
const masked = (service as any).maskTgId(555000111);
console.log(`  555000111 → ${masked}`);
console.log(`  стабильно: ${masked === (service as any).maskTgId(555000111) ? 'да ✅' : 'нет ❌'}`);
console.log(`  ID не виден: ${!masked.includes('555000111') ? 'да ✅' : 'нет ❌'}`);

void prisma.$disconnect();
