# Luna — дизайн REST API

**База:** `https://api.luna.uz/api/v1`
**Формат:** JSON, UTF-8. Все даты — ISO 8601. Суммы — строки (`"288000.00"`), чтобы не терять точность в JavaScript-числах.

---

## 1. Общие правила

### Аутентификация

Каждый запрос, кроме помеченных `@Public`, требует заголовок:

```
Authorization: Bearer <access_token>
```

Access-токен живёт 15 минут. При `401` клиент дёргает `POST /auth/refresh` и повторяет запрос — это делает `AuthInterceptor` в Flutter, экраны об этом не знают.

### Формат ответа

Успех — данные напрямую, без обёртки `{ data: ... }`:

```json
{ "id": "9f3c...", "name": "Кроссовки Спорт-12", "salePrice": "450000.00" }
```

Списки — с метаданными пагинации:

```json
{
  "items": [ ... ],
  "meta": { "page": 1, "limit": 20, "total": 143, "totalPages": 8 }
}
```

Ошибка — единый формат:

```json
{
  "statusCode": 422,
  "code": "INSUFFICIENT_STOCK",
  "message": "На складе только 8 пар модели «Спорт-12»",
  "details": { "productId": "9f3c...", "available": 8, "requested": 12 },
  "timestamp": "2026-08-01T10:23:45.123Z",
  "path": "/api/v1/sales"
}
```

`message` — **готовый к показу пользователю текст на его языке** (заголовок `Accept-Language: uz|ru`). `code` — машинный идентификатор для клиентской логики. Без этого разделения Flutter будет парсить строки, а это всегда заканчивается плохо.

### Коды ошибок

| HTTP | `code` | Когда |
|---|---|---|
| 400 | `VALIDATION_ERROR` | не прошла zod-схема, `details` содержит поля |
| 401 | `UNAUTHORIZED` / `TOKEN_EXPIRED` | нет или протух токен |
| 403 | `FORBIDDEN_ROLE` | роль не имеет права на операцию |
| 403 | `SUBSCRIPTION_EXPIRED` | подписка компании закончилась |
| 404 | `NOT_FOUND` | сущность не найдена **или принадлежит другой компании** |
| 409 | `DUPLICATE_SKU` / `TELEGRAM_ALREADY_LINKED` | нарушение уникальности |
| 422 | `INSUFFICIENT_STOCK` | не хватает остатка |
| 422 | `PERIOD_ALREADY_CLOSED` | попытка изменить закрытый зарплатный период |
| 422 | `INVALID_STATUS_TRANSITION` | недопустимый переход статуса заказа |
| 429 | `TOO_MANY_REQUESTS` | rate limit |

**Важно:** чужая сущность отдаёт `404`, а не `403`. Иначе по коду ответа можно перебором выяснить, какие ID существуют в других компаниях.

### Пагинация, фильтры, сортировка

```
GET /products?page=1&limit=20&search=спорт&isActive=true&sort=-createdAt
```

- `page` (с 1), `limit` (по умолчанию 20, максимум 100)
- `sort` — поле, префикс `-` = по убыванию
- `dateFrom` / `dateTo` — везде, где есть период (формат `YYYY-MM-DD`, границы включительно)

### Идемпотентность

Операции, создающие деньги или движение склада (`POST /sales`, `POST /expenses`, `POST /salary-payments`), принимают заголовок:

```
Idempotency-Key: <uuid клиента>
```

Повтор с тем же ключом в течение 24 часов возвращает первый результат, а не создаёт вторую продажу. Нужно потому, что мобильная сеть в цехе отваливается, пользователь жмёт «Сохранить» второй раз, и без этого касса разъедется.

### Роли

`O` = OWNER, `A` = ADMIN, `B` = ACCOUNTANT (бухгалтер). Если колонка не указана — доступ у всех троих.

---

## 2. Auth

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| POST | `/auth/register` | — | регистрация компании + владельца |
| POST | `/auth/login` | — | вход |
| POST | `/auth/refresh` | — | обновление токенов |
| POST | `/auth/logout` | все | отзыв refresh-токена |
| GET | `/auth/me` | все | текущий пользователь + компания |
| PATCH | `/auth/password` | все | смена пароля |

### `POST /auth/register`

Создаёт компанию, владельца и **стартовые данные**: кассу «Основная», категории расходов, базовые операции. Без этого первый экран пустой и непонятный.

```json
// Запрос
{
  "companyName": "Luna Shoes",
  "fullName": "Рустам Абдувахобов",
  "phone": "+998901234567",
  "password": "…"
}

// 201
{
  "accessToken": "eyJhbGci…",
  "refreshToken": "8f2a9c…",
  "user": {
    "id": "3b1e…",
    "fullName": "Рустам Абдувахобов",
    "phone": "+998901234567",
    "role": "OWNER"
  },
  "company": {
    "id": "7c4d…",
    "name": "Luna Shoes",
    "plan": "TRIAL",
    "subscriptionEndsAt": "2026-08-15T00:00:00.000Z"
  }
}
```

### `POST /auth/login`

```json
// Запрос
{ "phone": "+998901234567", "password": "…" }
```

Rate limit: 5 попыток / 15 мин на связку телефон + IP. Ответ идентичен `/register`.

### `POST /auth/refresh`

```json
// Запрос
{ "refreshToken": "8f2a9c…" }

// 200 — оба токена новые (ротация)
{ "accessToken": "eyJhbGci…", "refreshToken": "1d7b3e…" }
```

Старый refresh немедленно отзывается. Повторное использование отозванного токена = признак кражи → отзывается вся семья токенов, пользователь разлогинивается везде.

---

## 3. Сотрудники и Telegram

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/employees` | O A B | список |
| POST | `/employees` | O A | создать |
| GET | `/employees/:id` | O A B | карточка + статистика |
| PATCH | `/employees/:id` | O A | изменить |
| DELETE | `/employees/:id` | O | уволить (мягкое удаление) |
| POST | `/employees/:id/telegram-link` | O A | сгенерировать код привязки |
| DELETE | `/employees/:id/telegram-link` | O A | отвязать Telegram |
| GET | `/employees/:id/stats` | O A B | выработка и заработок за период |

### `POST /employees/:id/telegram-link`

```json
// 201
{
  "code": "A7F3K9",
  "deepLink": "https://t.me/luna_workshop_bot?start=A7F3K9",
  "qrData": "https://t.me/luna_workshop_bot?start=A7F3K9",
  "expiresAt": "2026-08-02T10:00:00.000Z"
}
```

Приложение показывает QR — рабочий сканирует камерой телефона и попадает прямо в бота. Диктовать код голосом тоже можно, поэтому он короткий и без похожих символов (`0/O`, `1/I` исключены).

### `GET /employees/:id/stats?dateFrom=2026-07-01&dateTo=2026-07-31`

```json
{
  "employee": { "id": "5a2f…", "fullName": "Азиз Каримов" },
  "period": { "from": "2026-07-01", "to": "2026-07-31" },
  "totalUnits": 1240,
  "totalAmount": "14880000.00",
  "pendingUnits": 48,
  "advancePaid": "5000000.00",
  "toPay": "9880000.00",
  "byProduct": [
    { "productId": "9f3c…", "productName": "Спорт-12", "units": 820, "amount": "9840000.00" }
  ],
  "byDay": [
    { "date": "2026-07-01", "units": 42, "amount": "504000.00" }
  ]
}
```

`byDay` сразу в формате для графика — Flutter не должен агрегировать данные сам.

---

## 4. Выработка (work logs)

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/work-logs` | O A B | список с фильтрами |
| POST | `/work-logs` | O A | ручной ввод |
| GET | `/work-logs/pending` | O A | очередь на подтверждение |
| POST | `/work-logs/:id/approve` | O A | подтвердить |
| POST | `/work-logs/:id/reject` | O A | отклонить с причиной |
| POST | `/work-logs/bulk-approve` | O A | подтвердить пачкой |
| DELETE | `/work-logs/:id` | O | удалить (только `PENDING`) |

### `GET /work-logs?status=PENDING&employeeId=…&dateFrom=…&dateTo=…`

```json
{
  "items": [
    {
      "id": "c81a…",
      "employee": { "id": "5a2f…", "fullName": "Азиз Каримов" },
      "product": { "id": "9f3c…", "name": "Спорт-12", "sku": "SP-12" },
      "operation": { "id": "2e7b…", "name": "Затяжка" },
      "quantity": 24,
      "rate": "12000.00",
      "amount": "288000.00",
      "workDate": "2026-08-01",
      "status": "PENDING",
      "source": "TELEGRAM",
      "createdAt": "2026-08-01T14:32:10.000Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 7, "totalPages": 1 },
  "summary": { "totalQuantity": 168, "totalAmount": "2016000.00" }
}
```

`summary` считается по **всей выборке с учётом фильтров**, а не по текущей странице. Владельцу нужна сумма за месяц, а не за 20 видимых строк.

### `POST /work-logs/bulk-approve`

```json
// Запрос
{ "ids": ["c81a…", "d92b…", "e03c…"] }

// 200
{ "approved": 3, "failed": [] }
```

Утром админ подтверждает вчерашние отчёты одним нажатием — по одному это 20 тапов.

### `POST /work-logs` (ручной ввод)

```json
{
  "employeeId": "5a2f…",
  "productId": "9f3c…",
  "operationId": "2e7b…",
  "quantity": 24,
  "workDate": "2026-08-01",
  "rate": "12000.00"   // необязательно: если не передан — резолвится из piece_rates
}
```

Созданная админом запись сразу `APPROVED` — он сам себе подтверждающий.

---

## 5. Зарплата

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/payroll/periods` | O B | список периодов |
| POST | `/payroll/periods` | O B | открыть период |
| GET | `/payroll/periods/:id` | O B | период + начисления |
| POST | `/payroll/periods/:id/calculate` | O B | пересчитать (только `OPEN`) |
| POST | `/payroll/periods/:id/close` | O B | закрыть |
| PATCH | `/payroll/entries/:id` | O B | премия / удержание |
| GET | `/payroll/preview` | O B | что начислится, без создания периода |
| POST | `/salary-payments` | O B | выплатить (аванс/зарплата/премия) |
| GET | `/salary-payments` | O B | история выплат |

### `POST /payroll/periods/:id/calculate`

Собирает `APPROVED` work-logs периода с `payrollEntryId IS NULL`, группирует по сотрудникам, создаёт/обновляет `payroll_entries`.

```json
// 200
{
  "periodId": "4d8e…",
  "status": "OPEN",
  "totalAmount": "48720000.00",
  "entries": [
    {
      "id": "7f1c…",
      "employee": { "id": "5a2f…", "fullName": "Азиз Каримов" },
      "workAmount": "14880000.00",
      "bonus": "0.00",
      "deduction": "0.00",
      "totalAccrued": "14880000.00",
      "advancePaid": "5000000.00",
      "toPay": "9880000.00",
      "isPaid": false
    }
  ]
}
```

`calculate` можно вызывать сколько угодно раз, пока период `OPEN` — идемпотентен. `close` проставляет `payrollEntryId` в work-logs, после чего они больше никогда не попадут в другой период.

### `POST /salary-payments`

```json
// Запрос
{
  "employeeId": "5a2f…",
  "type": "ADVANCE",           // ADVANCE | SALARY | BONUS
  "amount": "5000000.00",
  "paidAt": "2026-08-15",
  "cashAccountId": "1a2b…",
  "note": "Аванс за август"
}
```

В одной транзакции: `salary_payments` + `cash_transactions(OUT, SALARY)` + баланс кассы + `payroll_entries.advancePaid`. Отдельно «записать в кассу» не нужно — и не получится, это единственный путь.

---

## 6. Товары и склад

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/products` | все | список |
| POST | `/products` | O A | создать |
| GET | `/products/:id` | все | карточка |
| PATCH | `/products/:id` | O A | изменить |
| DELETE | `/products/:id` | O | архивировать |
| GET | `/products/low-stock` | O A | заканчивающиеся |
| GET | `/products/:id/movements` | O A | история движений |
| POST | `/stock/movements` | O A | приход / списание / инвентаризация |

### `POST /stock/movements`

```json
{
  "productId": "9f3c…",
  "type": "PRODUCTION_IN",     // PRODUCTION_IN | PURCHASE_IN | WRITE_OFF | ADJUSTMENT | RETURN_IN
  "quantity": 50,              // для ADJUSTMENT — итоговый остаток, для остальных — дельта
  "note": "Выпуск партии 01.08"
}
```

```json
// 201
{
  "id": "b73f…",
  "type": "PRODUCTION_IN",
  "quantity": 50,
  "balanceAfter": 138,
  "createdAt": "2026-08-01T16:00:00.000Z"
}
```

`ADJUSTMENT` трактуется иначе остальных: клиент присылает **фактический остаток после пересчёта**, сервер сам вычисляет дельту. Кладовщик считает пары, а не разницу — интерфейс обязан совпадать с реальным действием.

---

## 7. Заказы

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/orders` | все | список |
| POST | `/orders` | O A | создать |
| GET | `/orders/:id` | все | карточка |
| PATCH | `/orders/:id` | O A | изменить |
| POST | `/orders/:id/status` | O A | сменить статус |
| DELETE | `/orders/:id` | O | отменить |
| GET | `/orders/overdue` | O A | просроченные |

### Автомат статусов

```
NEW ──► IN_PROGRESS ──► READY ──► ISSUED
 │           │            │
 └───────────┴────────────┴──────► CANCELLED
```

Назад ходить нельзя (кроме `CANCELLED`), `ISSUED` — терминальный. Недопустимый переход → `422 INVALID_STATUS_TRANSITION`. Логика в сервисе, а не в клиенте: приложение просто получает список разрешённых переходов в поле `availableTransitions`.

### `GET /orders/:id`

```json
{
  "id": "e5a1…",
  "orderNumber": 14,
  "status": "IN_PROGRESS",
  "availableTransitions": ["READY", "CANCELLED"],
  "customer": { "id": "aa11…", "name": "Магазин «Оламон»", "phone": "+998971112233" },
  "dueDate": "2026-08-20",
  "isOverdue": false,
  "totalAmount": "13500000.00",
  "prepaidAmount": "5000000.00",
  "debt": "8500000.00",
  "progress": { "ordered": 30, "produced": 18, "percent": 60 },
  "items": [
    {
      "id": "f0b2…",
      "product": { "id": "9f3c…", "name": "Спорт-12", "sku": "SP-12" },
      "quantity": 30,
      "producedQuantity": 18,
      "unitPrice": "450000.00",
      "total": "13500000.00"
    }
  ]
}
```

`progress`, `debt`, `isOverdue` считает сервер. Дублировать эти вычисления в Flutter — гарантия расхождения цифр между экранами.

### `POST /orders/:id/status` при переходе в `ISSUED`

Списывает товар со склада (`ORDER_OUT`) и, если передан `createSale: true`, создаёт продажу с приходом в кассу:

```json
{ "status": "ISSUED", "createSale": true, "cashAccountId": "1a2b…", "paidAmount": "8500000.00" }
```

---

## 8. Продажи

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/sales` | O B | список |
| POST | `/sales` | O A B | оформить продажу |
| GET | `/sales/:id` | O B | карточка |
| DELETE | `/sales/:id` | O | сторнировать |

### `POST /sales`

```json
{
  "customerId": "aa11…",          // опционально
  "soldAt": "2026-08-01T17:30:00.000Z",
  "paymentMethod": "CASH",        // CASH | CARD | TRANSFER | DEBT
  "cashAccountId": "1a2b…",
  "discount": "0.00",
  "paidAmount": "3600000.00",
  "items": [
    { "productId": "9f3c…", "quantity": 8, "unitPrice": "450000.00" }
  ]
}
```

Одна транзакция делает всё: проверяет остаток, списывает склад (`SALE_OUT`), фиксирует `cost_price_snapshot` из `products.costPrice`, создаёт `cash_transactions(IN, SALE)` если оплата не `DEBT`, обновляет баланс кассы, инкрементит номер продажи.

```json
// 201
{
  "id": "d4c8…",
  "saleNumber": 203,
  "totalAmount": "3600000.00",
  "totalCost": "2240000.00",
  "grossProfit": "1360000.00",
  "paidAmount": "3600000.00",
  "debt": "0.00",
  "items": [ … ]
}
```

Прибыль отдаём сразу — владелец хочет видеть, сколько заработал на этой продаже, а не считать в уме.

**Ошибка нехватки остатка** (`422`) содержит всё для внятного сообщения:

```json
{
  "code": "INSUFFICIENT_STOCK",
  "message": "На складе только 5 пар модели «Спорт-12»",
  "details": { "productId": "9f3c…", "productName": "Спорт-12", "available": 5, "requested": 8 }
}
```

`DELETE /sales/:id` — не физическое удаление, а сторно: возврат товара на склад (`RETURN_IN`) и обратная транзакция в кассе. Финансовая история не переписывается.

---

## 9. Касса и расходы

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/cash/accounts` | O B | кассы и балансы |
| POST | `/cash/accounts` | O | создать кассу |
| GET | `/cash/transactions` | O B | журнал операций |
| POST | `/cash/transactions` | O B | ручная операция (внесение/изъятие) |
| GET | `/cash/summary` | O B | сводка за период |
| GET | `/expenses` | O B | расходы |
| POST | `/expenses` | O A B | добавить расход |
| PATCH | `/expenses/:id` | O B | изменить |
| DELETE | `/expenses/:id` | O | удалить (сторнирует кассу) |
| GET | `/expense-categories` | O A B | категории |
| POST | `/expense-categories` | O B | создать категорию |

### `GET /cash/summary?dateFrom=2026-08-01&dateTo=2026-08-31`

```json
{
  "openingBalance": "12400000.00",
  "income":  { "total": "84300000.00", "bySale": "84300000.00", "other": "0.00" },
  "outcome": {
    "total": "61200000.00",
    "byCategory": [
      { "category": "SALARY",  "name": "Зарплата",   "amount": "48720000.00" },
      { "category": "EXPENSE", "name": "Аренда",     "amount": "8000000.00" },
      { "category": "EXPENSE", "name": "Коммуналка", "amount": "4480000.00" }
    ]
  },
  "closingBalance": "35500000.00",
  "accounts": [
    { "id": "1a2b…", "name": "Основная", "type": "CASH", "balance": "35500000.00" }
  ]
}
```

### `POST /expenses`

```json
{ "categoryId": "3c4d…", "amount": "8000000.00", "spentAt": "2026-08-01", "cashAccountId": "1a2b…", "note": "Аренда за август" }
```

Зарплату сюда вводить нельзя — она попадает в кассу только через `/salary-payments`. Категории `SALARY` в списке расходов не существует, иначе двойной учёт неизбежен.

---

## 10. Калькулятор себестоимости

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/materials` | O A | справочник материалов |
| POST | `/materials` | O A | добавить материал |
| POST | `/costing/calculate` | O A | расчёт без сохранения |
| POST | `/costing` | O A | сохранить расчёт |
| GET | `/costing` | O A | список расчётов |
| POST | `/costing/:id/apply` | O A | записать в `products.costPrice` |

### `POST /costing/calculate`

```json
// Запрос
{
  "productId": "9f3c…",
  "materials": [
    { "materialId": "m1…", "quantity": 2.5 },
    { "name": "Подошва", "unit": "пара", "quantity": 1, "unitPrice": "35000.00" }
  ],
  "laborCost": null,          // null → сервер сам сложит расценки всех операций модели
  "overheadCost": "15000.00",
  "timeMinutes": 45,
  "marginPercent": 30
}
```

```json
// 200 — ничего не сохраняется, чистый расчёт
{
  "materialsCost": "120000.00",
  "laborCost": "45000.00",
  "overheadCost": "15000.00",
  "totalCost": "180000.00",
  "marginPercent": "30.00",
  "recommendedPrice": "234000.00",
  "profitPerUnit": "54000.00",
  "breakdown": [
    { "name": "Кожа натуральная", "unit": "дм²", "quantity": "2.500", "unitPrice": "34000.00", "total": "85000.00" },
    { "name": "Подошва", "unit": "пара", "quantity": "1.000", "unitPrice": "35000.00", "total": "35000.00" }
  ],
  "laborBreakdown": [
    { "operation": "Затяжка", "rate": "12000.00" },
    { "operation": "Пошив", "rate": "18000.00" },
    { "operation": "Упаковка", "rate": "15000.00" }
  ]
}
```

Разделение `calculate` и `POST /costing` намеренное: владелец крутит маржу туда-сюда, глядя на цену. Каждое движение ползунка не должно создавать запись в БД.

`laborCost: null` — важная деталь: себестоимость работы берётся из **реальных расценок**, по которым платится зарплата. Иначе калькулятор начнёт врать в тот день, когда расценки поднимут.

---

## 11. Аналитика

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/analytics/dashboard` | O | главный экран |
| GET | `/analytics/profit` | O | прибыль по периодам |
| GET | `/analytics/top-products` | O A | топ товаров |
| GET | `/analytics/production` | O A | выпуск по дням/сотрудникам |

### `GET /analytics/dashboard?period=month`

Один запрос на весь главный экран — не пять. Мобильная сеть в цехе плохая, пять параллельных запросов дают пять шансов на ошибку.

```json
{
  "period": { "from": "2026-08-01", "to": "2026-08-31", "label": "Август 2026" },
  "revenue":     { "value": "84300000.00", "changePercent": 12.4 },
  "grossProfit": { "value": "31800000.00", "changePercent": 8.1 },
  "netProfit":   { "value": "23100000.00", "changePercent": -3.2 },
  "expenses":    { "value": "12480000.00", "changePercent": 5.0 },
  "salaries":    { "value": "48720000.00", "changePercent": 15.2 },
  "cashBalance": "35500000.00",
  "salaryDebt":  "9880000.00",
  "unitsProduced": 1240,
  "unitsSold": 1180,
  "alerts": {
    "pendingWorkLogs": 7,
    "lowStockProducts": 3,
    "overdueOrders": 1
  },
  "revenueChart": [
    { "date": "2026-08-01", "revenue": "3600000.00", "profit": "1360000.00" }
  ],
  "topProducts": [
    { "id": "9f3c…", "name": "Спорт-12", "unitsSold": 420, "revenue": "18900000.00", "profit": "7140000.00" }
  ]
}
```

`changePercent` — сравнение с предыдущим периодом той же длины. Абсолютная цифра без динамики владельцу мало что говорит.

`alerts` управляет бейджами в навигации: `pendingWorkLogs: 7` рисует красную точку на «Выработке».

---

## 12. Отчёты и уведомления

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| POST | `/reports/export` | O B | поставить отчёт в очередь |
| GET | `/reports/:jobId` | O B | статус и ссылка |
| GET | `/reports/:jobId/download` | O B | скачать готовый файл |
| GET | `/notifications` | все | список |
| POST | `/notifications/:id/read` | все | отметить прочитанным |
| POST | `/notifications/read-all` | все | прочитать все |
| POST | `/devices/push-token` | все | зарегистрировать FCM-токен |

### `POST /reports/export`

```json
{ "type": "SALES", "format": "XLSX", "dateFrom": "2026-08-01", "dateTo": "2026-08-31" }
```

`type`: `FINANCE` | `SALES` | `PAYROLL` | `PRODUCTION` | `STOCK`. `format`: `PDF` | `XLSX`.

```json
// 202 Accepted — генерация асинхронная
{ "jobId": "j-8a3f…", "status": "PENDING" }
```

```json
// GET /reports/j-8a3f… → 200
{
  "jobId": "j-8a3f…",
  "status": "READY",
  "type": "SALES",
  "format": "XLSX",
  "fileName": "sales-2026-08-01_2026-08-31.xlsx",
  "url": "/reports/j-8a3f…/download",
  "expiresAt": "2026-08-02T10:00:00.000Z"
}
```

`status`: `PENDING` | `READY` | `FAILED`. `url` появляется только вместе с `READY`.

Синхронная генерация не годится: годовой отчёт по зарплате — это секунды работы, HTTP-таймаут на плохой сети наступит раньше. Клиент показывает прогресс и открывает файл по готовности.

**Ссылка ведёт на нас, а не на внешнее хранилище с подписанным токеном.** Файл лежит на том же сервере, и обычной авторизации по заголовку достаточно; токен в URL пришлось бы прятать от логов прокси и истории браузера. Когда появится объектное хранилище, поменяется значение `url` — контракт остаётся прежним.

**Очередь живёт в памяти процесса, а не в Redis.** Задача существует полминуты, переживать перезапуск ей незачем: проще нажать «Экспорт» ещё раз, чем держать ради этого отдельный воркер в цехе, где бэкенд один. Файл удаляется через 30 минут — иначе папка отчётов растёт до конца диска. При нескольких инстансах менять придётся только реализацию: наружу это не видно.

### Уведомления

Создаёт их не пользователь, а сторож: раз в час он смотрит остатки ниже минимума и заказы с вышедшим сроком. Повторы гасятся ключом по составу списка — остаток остаётся низким неделями, и без этого к пятнице лента состояла бы из сорока одинаковых строк.

`userId = null` означает «для всех в компании»: «товар заканчивается» касается каждого, кто ведёт склад.

```json
// GET /notifications?unreadOnly=true → 200
{
  "items": [
    {
      "id": "n-1",
      "type": "LOW_STOCK",
      "title": "Товар заканчивается",
      "body": "Botinka «Qish-4» (3), Tufli «Klassika» (1)",
      "isRead": false,
      "createdAt": "2026-08-04T09:00:00.000Z"
    }
  ],
  "unread": 1
}
```

`POST /devices/push-token` токены принимает и хранит, но отправка push пока не подключена — для неё нужны ключи FCM. Уведомления доставляются в приложении.

---

## 13. Telegram (служебное)

| Метод | Путь | Доступ | Описание |
|---|---|---|---|
| POST | `/telegram/webhook/:secret` | Telegram | приём апдейтов |

Не часть публичного API. Защита: секретный сегмент пути + обязательный заголовок `X-Telegram-Bot-Api-Secret-Token`. Обработчик кладёт апдейт в очередь и отвечает `200` немедленно — иначе Telegram ретраит и рабочий получит двойную запись выработки.

---

## 14. Что реализуется в первую очередь

Порядок, при котором каждый шаг даёт работающий сценарий целиком:

1. `/auth/*` — без этого не проверить ничего
2. `/employees/*`, `/products/*`, `/operations`, `/piece-rates` — справочники
3. `/telegram/webhook` + `/work-logs/*` — **ядро продукта**, рабочие начинают отчитываться
4. `/payroll/*`, `/salary-payments` — зарплата считается сама
5. `/expenses`, `/cash/*` — касса сходится
6. `/orders/*`, `/sales/*`, `/costing/*`
7. `/analytics/*`, `/reports/*`, `/notifications`

После шага 3 системой уже можно пользоваться вместо блокнота — это первая точка, где её стоит показывать реальному цеху.
