# Luna — архитектура системы

**Продукт:** SaaS для управления обувным производственным цехом.
**Стек:** Flutter (Android-first) · NestJS (Node.js 20, TypeScript) · PostgreSQL 16 · REST API · Telegram Bot.

---

## 1. Общая картина

```
┌──────────────────┐        ┌──────────────────┐
│  Flutter App     │        │  Telegram Bot    │
│  (владелец,      │        │  (сотрудники)    │
│   администратор) │        │                  │
└────────┬─────────┘        └────────┬─────────┘
         │ REST + JWT                │ webhook (HTTPS)
         │                           │
         ▼                           ▼
┌─────────────────────────────────────────────────┐
│                 NestJS API                      │
│  Guards (JWT → Role → Tenant)                   │
│  Modules: auth, employees, work-logs, payroll,  │
│  orders, products, stock, sales, expenses,      │
│  cash, costing, analytics, reports, telegram,   │
│  notifications                                  │
└───────┬──────────────────────┬──────────────────┘
        │ Prisma               │ BullMQ (jobs)
        ▼                      ▼
┌────────────────┐     ┌────────────────┐
│  PostgreSQL    │     │  Redis         │
│  (single DB,   │     │  очереди,      │
│   company_id)  │     │  кэш, rate lim │
└────────────────┘     └────────────────┘
```

Один API-процесс, одна БД, один Telegram-бот на все компании. Разделение арендаторов — по колонке `company_id`.

### Почему так, а не микросервисы
MVP на 1–50 цехов держится одним инстансом NestJS без проблем. Микросервисы здесь дают только оверхед по деплою и распределённые транзакции там, где нужны обычные (списание склада + касса + продажа в одном коммите).

---

## 2. Backend: структура проекта

```
backend/
├── prisma/
│   ├── schema.prisma           # единственный источник правды по схеме
│   ├── migrations/
│   ├── sql/002_constraints.sql # partial-индексы, RLS, чего Prisma не умеет
│   └── seed.ts
├── src/
│   ├── main.ts
│   ├── app.module.ts
│   ├── common/
│   │   ├── decorators/         # @CurrentUser, @Roles, @Public
│   │   ├── guards/             # JwtAuthGuard, RolesGuard, TenantGuard
│   │   ├── interceptors/       # LoggingInterceptor, TransformInterceptor
│   │   ├── filters/            # PrismaExceptionFilter, AllExceptionsFilter
│   │   ├── pipes/              # ZodValidationPipe
│   │   └── dto/                # PaginationDto, DateRangeDto
│   ├── prisma/
│   │   ├── prisma.module.ts
│   │   ├── prisma.service.ts
│   │   └── tenant.middleware.ts  # авто-подстановка company_id
│   ├── config/                 # конфиг + валидация env через zod
│   └── modules/
│       ├── auth/               # login, refresh, register-company, me
│       ├── companies/          # тенанты, план, лимиты
│       ├── users/              # владелец/админ/бухгалтер
│       ├── employees/          # рабочие цеха + привязка Telegram
│       ├── operations/         # виды работ (затяжка, пошив, упаковка)
│       ├── piece-rates/        # расценки за единицу
│       ├── work-logs/          # отчёты о выработке (ядро зарплаты)
│       ├── payroll/            # периоды, начисления, выплаты
│       ├── products/           # модели обуви
│       ├── stock/              # движения склада (ledger)
│       ├── orders/             # заказы + позиции + статусы
│       ├── customers/
│       ├── sales/              # продажи
│       ├── expenses/           # расходы + категории
│       ├── cash/               # кассы и транзакции
│       ├── costing/            # калькулятор себестоимости
│       ├── analytics/          # дашборд, топ-товары, прибыль
│       ├── reports/            # PDF/Excel экспорт
│       ├── notifications/      # push + telegram + in-app
│       └── telegram/           # бот: webhook, сцены, привязка
└── test/
```

### Правила слоёв
Каждый модуль: `*.controller.ts` (HTTP, DTO, роли) → `*.service.ts` (бизнес-логика, транзакции) → Prisma. Репозиторный слой не вводим — Prisma сам по себе уже репозиторий, лишняя абстракция в MVP только мешает.

Кросс-модульные операции (продажа → склад → касса) собираются в одном сервисе через `prisma.$transaction`, а не через события. События (BullMQ) — только для того, что можно потерять и переиграть: уведомления, экспорт отчётов, рассылка в Telegram.

### Мультиарендность
Три уровня защиты:

1. **`TenantGuard`** кладёт `companyId` из JWT в `AsyncLocalStorage`.
2. **Prisma middleware** автоматически добавляет `where.companyId` во все `find*`/`update*`/`delete*` и `data.companyId` во все `create` для моделей, помеченных как арендуемые.
3. **Postgres RLS** (включаем перед выходом на платящих клиентов) — страховка от бага в п.2.

```ts
// src/prisma/tenant.middleware.ts
const TENANT_MODELS = new Set([
  'Employee','Product','Order','Sale','WorkLog','Expense',
  'CashTransaction','StockMovement','Customer','Operation',
  'PieceRate','PayrollPeriod','PayrollEntry','SalaryPayment',
  'CashAccount','ExpenseCategory','Material','CostCalculation','Notification',
]);

export function tenantMiddleware(store: AsyncLocalStorage<TenantCtx>): Prisma.Middleware {
  return async (params, next) => {
    const ctx = store.getStore();
    if (!ctx?.companyId || !TENANT_MODELS.has(params.model ?? '')) return next(params);

    if (params.action === 'create') {
      params.args.data.companyId ??= ctx.companyId;
    } else if (params.action === 'createMany') {
      params.args.data = params.args.data.map((d: any) => ({ ...d, companyId: ctx.companyId }));
    } else {
      params.args ??= {};
      params.args.where = { ...params.args.where, companyId: ctx.companyId };
    }
    return next(params);
  };
}
```

Фоновые задачи (cron, обработка вебхуков Telegram) работают вне HTTP-контекста — там `companyId` проставляется явно через `store.run({ companyId }, fn)`.

### Аутентификация и роли

| Роль | Кто | Права |
|---|---|---|
| `SUPERADMIN` | мы (платформа) | все компании, биллинг |
| `OWNER` | владелец цеха | всё внутри своей компании, включая финансы |
| `ADMIN` | мастер/менеджер | заказы, склад, подтверждение выработки; **не видит** прибыль и зарплатный фонд целиком |
| `ACCOUNTANT` | бухгалтер | касса, расходы, зарплата, отчёты; не меняет заказы |

- Вход по **телефону + пароль** (для Узбекистана это привычнее email).
- Access-token JWT, TTL 15 мин, payload: `{ sub, companyId, role }`.
- Refresh-token — случайные 32 байта, в БД хранится только SHA-256 хеш, TTL 30 дней, ротация при каждом использовании (обнаружение повторного использования → отзыв всей семьи токенов).
- Пароли — `argon2id`.
- Rate limit на `/auth/login`: 5 попыток / 15 мин на телефон + IP.

---

## 3. Telegram-бот: архитектура

Рабочие не заходят в приложение — только бот. Это единственный интерфейс ввода выработки, поэтому он обязан быть проще, чем набор команд.

### Режим работы
- **Prod: webhook.** `POST /telegram/webhook/:secretPath`, плюс проверка заголовка `X-Telegram-Bot-Api-Secret-Token`. Без long-polling: не держим соединение, легко масштабируется, не дублируется при нескольких инстансах.
- **Dev: polling** (тот же код, другой транспорт — библиотека `grammY`, у неё это переключается одной строкой).

Обработчик вебхука **не делает бизнес-логику синхронно**: кладёт апдейт в BullMQ и сразу отвечает `200`. Telegram ретраит при таймауте — иначе получим дубли отчётов.

### Привязка сотрудника (worker ↔ Telegram)
Никаких «введи свой ID». Одноразовый код:

1. Админ в приложении открывает сотрудника → «Подключить Telegram» → бэкенд создаёт запись в `telegram_link_codes`: 6 цифр, TTL 24 ч, одноразовый.
2. Приложение показывает deep-link `https://t.me/luna_workshop_bot?start=A7F3K9` и QR — рабочий сканирует.
3. Бот получает `/start A7F3K9`, находит код: не истёк, не использован → записывает `employees.telegram_user_id = message.from.id`, помечает код использованным.
4. Всё дальнейшее общение авторизуется **только по `telegram_user_id`**. Незнакомый ID получает «Обратитесь к администратору» и больше ничего — ни списка моделей, ни названия компании.

Один Telegram-аккаунт = один сотрудник (`UNIQUE` на `telegram_user_id`). Отвязка (увольнение) — админ жмёт «Отключить», ID обнуляется.

### Сценарий отчёта о выработке
Основной путь — кнопки, а не текст:

```
Рабочий: [🔨 Отчёт]
Бот:     Какую модель делал?
         [Кроссовки «Спорт-12»] [Ботинки «Зима-4»] [Туфли «Классика»]
         ← показываем 8 последних моделей этого рабочего + «Показать все»
Рабочий: Кроссовки «Спорт-12»
Бот:     Какая операция?
         [Затяжка] [Пошив] [Упаковка]
         ← если у рабочего одна операция в профиле — шаг пропускается
Рабочий: Затяжка
Бот:     Сколько пар?
Рабочий: 24
Бот:     ✅ Записано: Спорт-12 / Затяжка / 24 пары
         По расценке 12 000 сум = 288 000 сум
         Ожидает подтверждения мастера.
         [Отменить]
```

Быстрый текстовый ввод для опытных — тоже поддерживаем: `Спорт-12 24` (модель + количество, операция берётся из профиля).

Команды:

| Команда | Действие |
|---|---|
| `/start <код>` | привязка аккаунта |
| `/start` | главное меню |
| `/report` | мастер отчёта |
| `/today` | что записано сегодня |
| `/month` | выработка и сумма за текущий период |
| `/help` | инструкция на узбекском/русском |

### Подтверждение админом
`work_logs.status`: `PENDING` → `APPROVED` / `REJECTED`. Настройка компании `work_log_auto_approve` (bool): в маленьком цехе владелец доверяет — включает автоподтверждение, тогда запись сразу `APPROVED`. При отклонении бот пишет рабочему причину.

В зарплату попадают **только `APPROVED`**.

### Защита от дублей и злоупотреблений
- `UNIQUE (telegram_update_id)` на входящих апдейтах — идемпотентность ретраев Telegram.
- Лимит: 30 сообщений/мин на `telegram_user_id`, при превышении — молчание.
- Отмена своей записи — только в течение 30 минут и только пока `PENDING`.
- Аномалия (количество > 3× среднего за 30 дней) → запись создаётся, но админ получает уведомление «проверьте».

### Мультиарендность бота
Один бот на всех. Компания определяется через `employees.company_id` найденного по `telegram_user_id` сотрудника. Отдельные боты на компанию — только для платного тарифа позже (там же и брендирование).

---

## 4. Frontend: Flutter

### Выбор state management — Riverpod

Беру **Riverpod 2 (`flutter_riverpod` + `riverpod_generator`)**. Обоснование, а не вкусовщина:

| | Provider | Bloc | **Riverpod** |
|---|---|---|---|
| Зависимость от `BuildContext` | да, `ProviderNotFoundException` в рантайме | нет | нет, ошибки на этапе компиляции |
| Асинхронные данные (а тут почти всё — сеть) | руками `FutureBuilder` + ручной loading/error | `Cubit` + freezed-состояния, много кода | `AsyncValue` из коробки: `data/loading/error` |
| Кэш и инвалидация (дашборд, списки) | нет | руками | `ref.invalidate`, `keepAlive`, автодиспоз |
| Объём кода на один экран CRUD | средний | большой (событие+состояние+блок) | малый |
| Тестируемость | средняя | высокая | высокая (`ProviderContainer` с оверрайдами) |

Bloc оправдан там, где сложные конечные автоматы UI. Здесь 90% экранов — «загрузи список, отфильтруй, отправь форму». Riverpod закрывает это меньшим количеством кода и без рантайм-сюрпризов. Provider отпадает: он вынуждает писать ручную обработку loading/error на каждом асинхронном экране, а таких экранов здесь почти все.

### Структура

```
app/lib/
├── main.dart
├── core/
│   ├── api/
│   │   ├── dio_client.dart          # baseUrl, timeouts, интерцепторы
│   │   ├── auth_interceptor.dart    # Bearer + авто-refresh на 401
│   │   └── api_exception.dart
│   ├── router/app_router.dart       # go_router, guard по auth+роли
│   ├── storage/secure_storage.dart  # flutter_secure_storage для токенов
│   ├── theme/                       # цвета, типографика, компоненты
│   ├── format/                      # money (UZS), даты, числа
│   └── widgets/                     # AppButton, AppTextField, EmptyState,
│                                    # ErrorView, AsyncValueBuilder
├── features/
│   ├── auth/          { data/ domain/ presentation/ }
│   ├── dashboard/
│   ├── employees/
│   ├── work_logs/
│   ├── payroll/
│   ├── orders/
│   ├── products/
│   ├── sales/
│   ├── expenses/
│   ├── cash/
│   ├── costing/
│   ├── analytics/
│   ├── reports/
│   └── settings/
└── l10n/            # uz (основной), ru, en
```

Внутри фичи:
```
features/orders/
├── data/
│   ├── orders_api.dart        # только HTTP
│   └── order_dto.dart         # freezed + json_serializable
├── domain/
│   └── order.dart             # модель, к которой обращается UI
└── presentation/
    ├── providers/orders_provider.dart   # @riverpod AsyncNotifier
    ├── orders_screen.dart
    ├── order_detail_screen.dart
    └── widgets/order_card.dart
```

### Пакеты
`flutter_riverpod`, `riverpod_annotation` + `riverpod_generator`, `go_router`, `dio`, `freezed` + `json_serializable`, `flutter_secure_storage`, `intl`, `fl_chart` (аналитика), `firebase_messaging` (push), `share_plus` + `open_filex` (экспорт отчётов), `cached_network_image`.

### Типовой провайдер

```dart
@riverpod
class OrdersController extends _$OrdersController {
  @override
  Future<List<Order>> build(OrderStatus? status) async {
    return ref.watch(ordersApiProvider).list(status: status);
  }

  Future<void> changeStatus(String id, OrderStatus next) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(ordersApiProvider).updateStatus(id, next);
      ref.invalidate(dashboardProvider);          // дашборд пересчитается
      return ref.read(ordersApiProvider).list(status: status);
    });
  }
}
```

### Оффлайн
В MVP — **не делаем полноценный оффлайн-режим**. Владелец работает из цеха/дома со связью, а критичный ввод (выработка) идёт через Telegram, который сам умеет очередь. Делаем только: кэш последнего дашборда в `shared_preferences` + понятный экран «нет сети» с ретраем. Полноценная синхронизация — это отдельный большой кусок, в MVP он не окупается.

---

## 5. Ключевые бизнес-правила (чтобы не разъехалось)

1. **Деньги** — `numeric(14,2)`, в коде `Decimal` (`decimal.js` через Prisma). Никаких `float`. В Dart — `Decimal` из пакета `decimal` либо целые в сумах.
2. **Зарплата не вводится руками.** Источник — `work_logs` со статусом `APPROVED`, ставка фиксируется в момент записи (`work_logs.rate`), чтобы изменение расценки задним числом не переписало историю.
3. **Склад — это журнал.** Любое изменение остатка = строка в `stock_movements` + обновление `products.stock_quantity` в одной транзакции. Остаток никогда не правится напрямую; «инвентаризация» — это движение типа `ADJUSTMENT`.
4. **Касса — тоже журнал.** Продажа, расход, выплата зарплаты создают `cash_transactions`. Баланс кассы = сумма транзакций (денормализованный `balance` пересчитывается в той же транзакции).
5. **Себестоимость фиксируется в момент продажи** (`sale_items.cost_price_snapshot`), иначе прибыль за прошлый месяц будет меняться при каждом пересчёте калькулятора.
6. **Мягкое удаление** (`deleted_at`) — для справочников (товары, сотрудники, категории). Транзакционные записи не удаляются, только сторнируются.

---

## 6. Пошаговый план разработки (6 недель до рабочего MVP)

**Неделя 1 — фундамент**
- NestJS-скелет, Prisma-схема, миграции, seed.
- Auth: регистрация компании, логин, refresh, guards, роли.
- CI: lint + тесты, docker-compose (postgres + redis), деплой на staging.
- Flutter: скелет, роутер, dio + интерцепторы, экраны логина.

**Неделя 2 — справочники и склад**
- Backend: employees, operations, piece-rates, products, stock-movements.
- Flutter: список/карточка сотрудника, список/карточка товара, остатки.

**Неделя 3 — Telegram-бот и выработка** ← самый рискованный кусок, поэтому рано
- Бот на grammY, webhook, очередь, привязка по коду, мастер отчёта.
- `work-logs`: создание из бота, подтверждение/отклонение в приложении.
- Flutter: экран «Выработка» с фильтром по дате и сотруднику, кнопки подтверждения.

**Неделя 4 — деньги**
- Payroll: периоды, автоматический расчёт, авансы, выплаты.
- Expenses + категории, cash-accounts + cash-transactions.
- Flutter: касса, расходы, зарплата.

**Неделя 5 — заказы, продажи, себестоимость**
- Orders + order-items + статусы, customers.
- Sales с списанием склада и приходом в кассу.
- Costing-калькулятор.
- Flutter: соответствующие экраны.

**Неделя 6 — аналитика, отчёты, уведомления, релиз**
- Analytics-эндпоинты (дашборд, топ-товары, прибыль по периодам).
- Экспорт PDF/Excel через очередь.
- Уведомления: низкий остаток, просроченный заказ (cron) → push + Telegram.
- Полировка, тестирование на реальном цехе, сборка APK.

Приоритет при нехватке времени: режем экспорт отчётов и push (остаётся Telegram), но **не** режем work-logs, кассу и заказы — это ядро ценности.

---

## 7. Масштабирование и превращение в SaaS

**Что уже заложено:** `company_id` везде, план и статус подписки в `companies`, роли, единый бот, отсутствие жёсткой привязки к одному цеху.

**Что добавляем при первых платящих клиентах:**
- Postgres RLS поверх middleware (см. `prisma/sql/002_constraints.sql`).
- Тарифы и лимиты (`plan`, `max_employees`, `max_products`) + `PlanGuard` на создание сущностей.
- Биллинг: Payme/Click для Узбекистана, вебхук оплаты → продление `subscription_ends_at`.
- Онбординг: регистрация цеха за 2 минуты + демо-данные одной кнопкой.
- Суперадмин-панель: список компаний, активность, продления.

**Когда упрёмся в производительность (не раньше сотен цехов):**
- Read-реплика для аналитики и отчётов.
- Партиционирование `work_logs`, `cash_transactions`, `stock_movements` по месяцам.
- Материализованные представления дневных агрегатов вместо расчёта на лету.
- Вынос генерации отчётов и Telegram-воркера в отдельный процесс (код уже разделён очередями).

**Безопасность (делаем сразу, а не потом):**
- HTTPS-only, HSTS, `helmet`.
- Валидация всего входа через zod-схемы, никаких `any` в контроллерах.
- Секрет вебхука Telegram + проверка заголовка.
- Audit-log на финансовые операции (кто, что, когда, старое/новое значение).
- Бэкап БД: `pg_dump` ежедневно + PITR через WAL, проверка восстановления раз в месяц.
- Логи без ПДн и без токенов.
