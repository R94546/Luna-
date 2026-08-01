# Luna

SaaS для управления обувным производственным цехом: сотрудники и сдельная зарплата,
заказы, склад, продажи, касса, себестоимость и аналитика. Рабочие отчитываются
о выработке через Telegram-бота, владелец управляет всем из мобильного приложения.

**Стек:** Flutter (Android-first) · NestJS (Node.js 20, TypeScript) · PostgreSQL 16 · Redis · REST.

## Документация

| Документ | Содержание |
|---|---|
| [docs/01-architecture.md](docs/01-architecture.md) | архитектура backend и frontend, выбор state management, Telegram-бот, роли и авторизация, план разработки, путь к SaaS |
| [docs/02-database-schema.md](docs/02-database-schema.md) | схема БД: связи, ключевые решения, индексы, аналитические запросы, что упрощено в MVP |
| [docs/03-api-design.md](docs/03-api-design.md) | REST API: эндпоинты, форматы запросов и ответов, коды ошибок, идемпотентность |

## Структура

```
Luna/
├── docs/                            # техническая документация
├── backend/                         # NestJS API
│   ├── prisma/
│   │   ├── schema.prisma            # источник правды по схеме БД
│   │   ├── seed.ts                  # демо-данные для разработки
│   │   └── sql/002_constraints.sql  # CHECK, partial-индексы, триггер склада, RLS
│   ├── src/
│   │   ├── config/                  # валидация переменных окружения (zod)
│   │   ├── prisma/                  # PrismaService + изоляция арендаторов
│   │   ├── common/                  # guards, filters, pipes, decorators
│   │   └── modules/auth/            # регистрация, вход, refresh-ротация
│   └── test/
└── app/                             # Flutter-приложение (следующая итерация)
```

## Статус

- [x] Архитектура системы
- [x] Схема базы данных (30 таблиц, миграция применяется, инварианты проверены)
- [x] Дизайн REST API
- [x] Backend: скелет NestJS + авторизация + изоляция арендаторов
- [ ] Справочники: сотрудники, товары, операции, расценки
- [ ] Telegram-бот и учёт выработки
- [ ] Зарплата, касса, расходы
- [ ] Заказы, продажи, себестоимость
- [ ] Аналитика и отчёты
- [ ] Flutter-приложение

## Запуск

```bash
cd backend
cp .env.example .env          # укажите DATABASE_URL и JWT_SECRET
npm install

docker compose up -d          # postgres + redis

npx prisma migrate dev        # создаст таблицы

# CHECK-констрейнты, partial-индексы и триггер сверки склада —
# отдельной миграцией, т.к. Prisma их не генерирует
npx prisma migrate dev --create-only -n constraints
cat prisma/sql/002_constraints.sql >> prisma/migrations/*_constraints/migration.sql
npx prisma migrate dev

npm run seed                  # демо-данные
npm run start:dev             # http://localhost:3000/api/v1
```

**Демо-вход после seed:** `+998901234567` / `luna12345`

### Проверка изоляции арендаторов

Самый критичный механизм системы — данные одного цеха не должны быть видны другому:

```bash
DATABASE_URL=... npx ts-node test/tenant-isolation.manual.ts
```

## Что уже проверено на живой БД

- миграция схемы применяется с нуля, все 30 таблиц создаются;
- `002_constraints.sql` накатывается без ошибок;
- **триггер сверки склада** ловит попытку изменить остаток мимо журнала движений;
- `CHECK`-констрейнты не дают уйти в отрицательный остаток и записать выработку,
  где `amount ≠ quantity × rate`;
- регистрация, вход, `/auth/me`, ротация refresh-токена;
- повторное использование отозванного refresh-токена отзывает всю семью токенов;
- нормализация телефона: `901234567` → `+998901234567`;
- **изоляция компаний**: чужие записи не читаются и не изменяются даже при
  точном совпадении ID, `create` без `companyId` берёт его из контекста.
