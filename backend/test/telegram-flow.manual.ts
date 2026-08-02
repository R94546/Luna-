/**
 * Прогон сценария Telegram-бота без обращения к серверам Telegram.
 *
 * Бот создаётся с заранее заданным botInfo (чтобы не звать getMe) и
 * transformer'ом, который перехватывает исходящие вызовы API и складывает
 * их в массив. Логика при этом выполняется настоящая — те же обработчики,
 * что и в проде.
 *
 * Запуск (нужна БД с демо-данными):
 *   DATABASE_URL=... npx ts-node test/telegram-flow.manual.ts
 */
import { ConfigService } from '@nestjs/config';
import { Bot } from 'grammy';
import { Update, UserFromGetMe } from 'grammy/types';
import { PieceRatesService } from '../src/modules/piece-rates/piece-rates.service';
import { ReportHandler } from '../src/modules/telegram/handlers/report.handler';
import { StartHandler } from '../src/modules/telegram/handlers/start.handler';
import { SummaryHandler } from '../src/modules/telegram/handlers/summary.handler';
import { TelegramSessionService } from '../src/modules/telegram/telegram-session.service';
import { TelegramService } from '../src/modules/telegram/telegram.service';
import { WorkLogsService } from '../src/modules/work-logs/work-logs.service';
import { PrismaService } from '../src/prisma/prisma.service';

const WORKER_TG_ID = 555000111;
const STRANGER_TG_ID = 999888777;

const botInfo: UserFromGetMe = {
  id: 42,
  is_bot: true,
  first_name: 'Luna',
  username: 'luna_workshop_bot',
  can_join_groups: false,
  can_read_all_group_messages: false,
  supports_inline_queries: false,
  can_connect_to_business: false,
  has_main_web_app: false,
  has_topics_enabled: false,
  allows_users_to_create_topics: false,
  can_manage_bots: false,
  supports_join_request_queries: false,
};

/** Исходящие сообщения бота — то, что увидел бы рабочий. */
const sent: { method: string; text?: string; buttons: string[] }[] = [];

/**
 * update_id должен быть уникальным между прогонами: идемпотентность
 * бота отсеивает уже виденные апдейты, и фиксированная нумерация
 * привела бы к тому, что второй запуск теста молча ничего не делает.
 */
let updateId = Date.now() % 1_000_000_000;

function textUpdate(text: string, tgId = WORKER_TG_ID): Update {
  return {
    update_id: ++updateId,
    message: {
      message_id: updateId,
      date: Math.floor(Date.now() / 1000),
      chat: { id: tgId, type: 'private', first_name: 'Worker' },
      from: { id: tgId, is_bot: false, first_name: 'Worker', username: 'worker' },
      text,
      ...(text.startsWith('/')
        ? { entities: [{ type: 'bot_command' as const, offset: 0, length: text.split(' ')[0].length }] }
        : {}),
    },
  } as Update;
}

function callbackUpdate(data: string, tgId = WORKER_TG_ID): Update {
  return {
    update_id: ++updateId,
    callback_query: {
      id: String(updateId),
      from: { id: tgId, is_bot: false, first_name: 'Worker', username: 'worker' },
      chat_instance: 'test',
      data,
      message: {
        message_id: updateId,
        date: Math.floor(Date.now() / 1000),
        chat: { id: tgId, type: 'private', first_name: 'Worker' },
        from: botInfo,
        text: 'previous',
      },
    },
  } as Update;
}

function lastReply() {
  return sent.filter((s) => s.method === 'sendMessage').at(-1);
}

function show(label: string): void {
  const reply = lastReply();
  console.log(`\n── ${label} ──`);
  console.log(reply?.text ?? '(бот промолчал)');
  if (reply?.buttons.length) console.log('   [кнопки]', reply.buttons.join(' | '));
}

async function main(): Promise<void> {
  const prisma = new PrismaService();
  const config = new ConfigService({ TELEGRAM_BOT_TOKEN: '', TELEGRAM_WEBHOOK_URL: '' });

  // Ручная сборка вместо Nest-контейнера: тесту нужен доступ к боту,
  // чтобы подменить транспорт, а поднимать всё приложение ради этого дорого.
  const rates = new PieceRatesService(prisma);
  const workLogs = new WorkLogsService(prisma, rates);
  const sessions = new TelegramSessionService();

  const service = new TelegramService(
    prisma,
    config,
    new StartHandler(prisma),
    new ReportHandler(prisma, workLogs, sessions),
    new SummaryHandler(workLogs),
  );

  // Бот с заданным botInfo не вызывает getMe, поэтому сеть не нужна.
  const bot = new Bot('123456:TEST-TOKEN-NOT-REAL', { botInfo });

  bot.api.config.use(async (_prev, method, payload) => {
    const p = payload as Record<string, unknown>;
    const markup = p.reply_markup as { inline_keyboard?: { text: string }[][] } | undefined;

    sent.push({
      method,
      text: p.text as string | undefined,
      buttons: (markup?.inline_keyboard ?? []).flat().map((b) => b.text),
    });

    return { ok: true, result: { message_id: sent.length } } as never;
  });

  /* eslint-disable @typescript-eslint/no-explicit-any */
  (service as any).bot = bot;
  (service as any).registerHandlers(bot);
  /* eslint-enable @typescript-eslint/no-explicit-any */

  // Детерминированное начальное состояние. Прогон меняет профиль сотрудника
  // (шаг 18 снимает специализацию), поэтому исходные поля задаются явно,
  // а не берутся такими, какими их оставил предыдущий запуск.
  const tortish = await prisma.operation.findFirstOrThrow({ where: { name: 'Qolipga tortish' } });

  const employee = await prisma.employee.findFirstOrThrow({ where: { fullName: 'Aziz Karimov' } });
  await prisma.employee.update({
    where: { id: employee.id },
    data: {
      telegramUserId: null,
      telegramLinkedAt: null,
      defaultOperationId: tortish.id,
    },
  });
  employee.defaultOperationId = tortish.id;

  await prisma.telegramLinkCode.deleteMany({ where: { employeeId: employee.id } });

  console.log('═══ Сценарий рабочего в Telegram ═══');

  // 1. Незнакомый отправитель
  await service.handleUpdate(textUpdate('/start', STRANGER_TG_ID));
  show('1. Незнакомый пользователь пишет боту');

  // 2. Мастер выдаёт код привязки
  const code = 'A7F3K9';
  await prisma.telegramLinkCode.create({
    data: {
      companyId: employee.companyId,
      employeeId: employee.id,
      code,
      expiresAt: new Date(Date.now() + 86_400_000),
    },
  });

  await service.handleUpdate(textUpdate(`/start ${code}`));
  show('2. Рабочий переходит по ссылке привязки');

  // 3. Повторное использование того же кода другим человеком
  await service.handleUpdate(textUpdate(`/start ${code}`, STRANGER_TG_ID));
  show('3. Тот же код пытается использовать посторонний');

  // 4. Начало отчёта
  await service.handleUpdate(callbackUpdate('report'));
  show('4. Кнопка «Ish qaydi»');

  // 5. Выбор модели (у Азиза одна специализация — шаг операции пропускается)
  const product = await prisma.product.findFirstOrThrow({ where: { sku: 'SP-12' } });
  await service.handleUpdate(callbackUpdate(`p:${product.id}`));
  show('5. Выбрана модель');

  // 6. Ввод количества
  const before = await prisma.workLog.count({ where: { employeeId: employee.id } });
  const quantityUpdate = textUpdate('24');
  await service.handleUpdate(quantityUpdate);
  show('6. Введено количество');

  const after = await prisma.workLog.count({ where: { employeeId: employee.id } });
  console.log(`   записей выработки: ${before} → ${after}`);

  // 7. Идемпотентность: Telegram повторяет тот же апдейт
  await service.handleUpdate(quantityUpdate);
  const afterRetry = await prisma.workLog.count({ where: { employeeId: employee.id } });
  console.log(
    `\n── 7. Повтор того же update_id (ретрай Telegram) ──\n   записей: ${afterRetry} ${afterRetry === after ? '— дубля нет ✅' : '— ДУБЛЬ ❌'}`,
  );

  // 8. Проверяем, что записалось
  const log = await prisma.workLog.findFirstOrThrow({
    where: { employeeId: employee.id },
    orderBy: { createdAt: 'desc' },
    include: { product: true, operation: true },
  });
  console.log(
    `\n── 8. Что попало в базу ──\n   ${log.product.name} / ${log.operation.name} / ${log.quantity} juft` +
      `\n   ставка ${log.rate} × ${log.quantity} = ${log.amount}` +
      `\n   статус ${log.status}, источник ${log.source}`,
  );

  // 9. Быстрый ввод одной строкой
  await service.handleUpdate(textUpdate('Sport-12 30'));
  show('9. Быстрый ввод «Sport-12 30»');

  // 10. Сводка за сегодня
  await service.handleUpdate(textUpdate('/today'));
  show('10. Команда /today');

  // 11. Отмена последней записи
  const lastLog = await prisma.workLog.findFirstOrThrow({
    where: { employeeId: employee.id },
    orderBy: { createdAt: 'desc' },
  });
  await service.handleUpdate(callbackUpdate(`undo:${lastLog.id}`));
  show('11. Кнопка отмены');

  const exists = await prisma.workLog.findFirst({ where: { id: lastLog.id } });
  console.log(`   запись удалена: ${exists === null ? 'да ✅' : 'нет ❌'}`);

  // ── Ветки, которые появились/переехали при разбиении сервиса на handlers ──

  await service.handleUpdate(textUpdate('/report'));
  show('12. Команда /report');

  await service.handleUpdate(textUpdate('/month'));
  show('13. Команда /month');

  await service.handleUpdate(callbackUpdate('month'));
  show('14. Кнопка «Bu oy»');

  await service.handleUpdate(textUpdate('/help'));
  show('15. Команда /help');

  await service.handleUpdate(callbackUpdate('menu'));
  show('16. Callback menu');

  // Отмена посреди мастера: сессия должна очиститься, иначе следующее
  // случайное число рабочего запишется как выработка по забытым полям.
  await service.handleUpdate(callbackUpdate('report'));
  await service.handleUpdate(callbackUpdate(`p:${product.id}`));
  await service.handleUpdate(callbackUpdate('cancel'));
  show('17. Отмена посреди мастера');

  const beforeStray = await prisma.workLog.count({ where: { employeeId: employee.id } });
  await service.handleUpdate(textUpdate('7'));
  const afterStray = await prisma.workLog.count({ where: { employeeId: employee.id } });
  console.log(
    `   число «7» после отмены ${afterStray === beforeStray ? 'не записалось ✅' : 'ЗАПИСАЛОСЬ ❌'}`,
  );

  // Сотрудник без специализации — путь с явным выбором операции
  await prisma.employee.update({
    where: { id: employee.id },
    data: { defaultOperationId: null },
  });

  await service.handleUpdate(callbackUpdate('report'));
  await service.handleUpdate(callbackUpdate(`p:${product.id}`));
  show('18. Выбор модели без специализации в профиле');

  const operation = await prisma.operation.findFirstOrThrow({ where: { name: 'Tikish' } });
  await service.handleUpdate(callbackUpdate(`o:${operation.id}`));
  show('19. Выбрана операция');

  await service.handleUpdate(textUpdate('12'));
  show('20. Количество после явного выбора операции');

  await prisma.$disconnect();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
