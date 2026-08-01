# Luna — схема базы данных

**СУБД:** PostgreSQL 16.
**Источник правды:** [`backend/prisma/schema.prisma`](../backend/prisma/schema.prisma).
**Дополнения, которые Prisma не выражает:** [`backend/prisma/sql/002_constraints.sql`](../backend/prisma/sql/002_constraints.sql).

Этот документ объясняет *почему* схема такая — сам DDL смотрите в файлах выше.

---

## 1. Карта связей

```
companies ─┬─ users ─── refresh_tokens
           │         └─ push_tokens
           ├─ employees ──┬── telegram_link_codes
           │              └── work_logs ──┐
           ├─ operations ─────────────────┤
           ├─ piece_rates                 │
           ├─ products ───┬───────────────┤
           │              ├── stock_movements
           │              ├── order_items ─── orders ─── customers
           │              ├── sale_items  ─── sales  ───┘
           │              └── cost_calculations ─── cost_calculation_items ─── materials
           ├─ payroll_periods ─── payroll_entries ─┬─ work_logs (обратная ссылка)
           │                                       └─ salary_payments ─┐
           ├─ expense_categories ─── expenses ────────────────────────┤
           ├─ cash_accounts ─── cash_transactions ◄────────────────────┘
           ├─ notifications
           ├─ audit_logs
           └─ company_counters
```

Три «журнала» (append-only) образуют финансовый скелет системы:

| Журнал | Что фиксирует | Кто его двигает |
|---|---|---|
| `work_logs` | сколько сделал каждый рабочий | Telegram-бот, ручной ввод |
| `stock_movements` | каждое изменение остатка | производство, продажи, заказы, списание |
| `cash_transactions` | каждое движение денег | продажи, расходы, выплаты зарплаты |

Все остальные таблицы — либо справочники, либо агрегаты над этими тремя. Такая структура даёт главное: **любую цифру в отчёте можно разложить до конкретной операции**, а именно этого не хватает владельцу с блокнотом.

---

## 2. Мультиарендность

`company_id UUID NOT NULL` есть в **каждой** таблице с бизнес-данными. Не в дочерних (`order_items`, `sale_items`, `cost_calculation_items`) — они добираются через родителя, и дублировать там `company_id` значит создать возможность рассогласования.

Все составные индексы начинаются с `company_id` — это делает их применимыми и для «все заказы компании», и для «заказы компании за период».

Уникальность — всегда в пределах компании: `UNIQUE (company_id, sku)`, `UNIQUE (company_id, order_number)`, `UNIQUE (company_id, name)` для справочников. Глобально уникальны только `companies.slug`, `users.phone` (логин), `employees.telegram_user_id`.

`ON DELETE CASCADE` от `companies` вниз — чтобы удаление тенанта не оставляло сирот. Внутри компании каскад стоит только там, где дочерняя запись бессмысленна без родителя (`order_items` → `orders`). Ссылки на справочники (`work_logs.product_id`) — `RESTRICT` по умолчанию: товар с историей нельзя удалить физически, только пометить `deleted_at`.

---

## 3. Деньги и количества

| Что | Тип | Почему |
|---|---|---|
| Суммы | `numeric(14,2)` | до 999 млрд сумов; `float` для денег недопустим — округление ломает сходимость кассы |
| Количество пар | `integer` | обувь считается парами, дробей нет |
| Количество материала | `numeric(12,3)` | кожа в дм², клей в кг — нужны дроби |
| Проценты (маржа) | `numeric(5,2)` | до 999.99% |
| Время | `timestamptz(3)` | таймзона компании настраиваемая (`companies.timezone`), сервер живёт в UTC |
| Даты бизнес-событий | `date` | `work_date`, `spent_at`, `due_date`, `paid_at` — рабочий отчитывается за день, а не за момент |

Разделение `timestamptz` / `date` не косметика: «выработка за 3 августа» не должна зависеть от того, отправил ли рабочий отчёт в 23:50 или в 00:10 — поэтому `work_date` это `date`, задаваемая отдельно от `created_at`.

---

## 4. Ключевые узлы схемы

### 4.1 Расценки: `piece_rates`

Сдельная оплата в цехе устроена не «ставка у сотрудника», а «ставка за операцию над моделью». Затяжка кроссовок стоит дороже затяжки тапочек; опытному мастеру могут платить больше.

Разрешение ставки — от частного к общему:

```
1. (product_id, operation_id, employee_id)  → персональная ставка мастера на модель
2. (product_id, operation_id, NULL)         → ставка по модели
3. (NULL,       operation_id, NULL)         → базовая ставка операции
```

```sql
-- Резолв ставки на дату
SELECT rate FROM piece_rates
WHERE company_id = $1
  AND operation_id = $2
  AND (product_id  = $3 OR product_id  IS NULL)
  AND (employee_id = $4 OR employee_id IS NULL)
  AND valid_from <= $5
  AND (valid_to IS NULL OR valid_to >= $5)
ORDER BY (employee_id IS NOT NULL) DESC,
         (product_id  IS NOT NULL) DESC
LIMIT 1;
```

`valid_from` / `valid_to` дают историю расценок. Но защита от переписывания истории — не в них, а в следующем пункте.

### 4.2 Снимки значений (самое важное решение схемы)

Три поля намеренно дублируют данные из справочников:

| Поле | Дублирует | Зачем |
|---|---|---|
| `work_logs.rate` | `piece_rates.rate` | подняли расценку с 1 сентября — зарплата за август не должна вырасти задним числом |
| `sale_items.cost_price_snapshot` | `products.cost_price` | пересчитали калькулятор — прибыль прошлого квартала не должна измениться |
| `cost_calculation_items.name/unit_price` | `materials` | материал переименовали или удалили — старый расчёт обязан остаться читаемым |

Плюс `work_logs.amount` (= `quantity * rate`) и `sales.total_cost` — денормализация ради аналитики: сумма зарплатного фонда и валовая прибыль считаются без единого умножения и джойна. Целостность защищена CHECK-констрейнтом `amount = quantity * rate`.

Это не «избыточность», это единственный способ получить неизменяемую финансовую историю без event sourcing.

### 4.3 Склад: `stock_movements`

`products.stock_quantity` — денормализованный кэш. Правило без исключений: **остаток меняется только вместе со вставкой в `stock_movements`, в одной транзакции**.

```ts
// Списание при продаже
await prisma.$transaction(async (tx) => {
  const product = await tx.product.update({
    where: { id: productId },
    data: { stockQuantity: { decrement: qty } },   // атомарный decrement, без read-modify-write
  });

  await tx.stockMovement.create({
    data: {
      companyId, productId,
      type: 'SALE_OUT',
      quantity: -qty,                    // со знаком
      balanceAfter: product.stockQuantity,
      refType: 'sale', refId: saleId,
      createdById: userId,
    },
  });
});
```

`{ decrement: qty }` вместо чтения и записи убирает гонку между двумя одновременными продажами. `CHECK (stock_quantity >= 0)` не даст уйти в минус — попытка продать больше, чем есть, упадёт транзакцией, а не создаст отрицательный остаток.

Deferred constraint trigger `trg_stock_movement_balance` в конце каждой транзакции сверяет `products.stock_quantity` с суммой журнала. Если однажды кто-то напишет обновление остатка мимо журнала — узнаем сразу, а не через полгода при инвентаризации.

Инвентаризация — это не правка остатка, а движение типа `ADJUSTMENT` с разницей.

### 4.4 Касса: `cash_transactions`

Единый журнал денег. `amount` всегда положительный, направление — в `direction (IN|OUT)`. Отрицательные суммы запрещены CHECK-констрейнтом: так невозможно случайно записать «приход −500 000» и получить сходящийся, но неверный баланс.

Три источника создают транзакции автоматически, а не руками:

```
sales           → CashTransaction(IN,  SALE)     -- при оплате продажи
expenses        → CashTransaction(OUT, EXPENSE)  -- 1:1, expenses.cash_transaction_id UNIQUE
salary_payments → CashTransaction(OUT, SALARY)   -- 1:1
```

Связь `1:1` через `UNIQUE`-колонку `cash_transaction_id` гарантирует, что один расход не породит две записи в кассе. Ручные операции (владелец внёс/изъял деньги) — `INVESTMENT` / `WITHDRAWAL` без ссылки на источник.

Баланс кассы: `cash_accounts.balance` обновляется в той же транзакции. Сверка — `SUM(CASE direction WHEN 'IN' THEN amount ELSE -amount END)`.

### 4.5 Зарплата: три таблицы, а не одна

```
work_logs (APPROVED, payroll_entry_id IS NULL)   ← что заработано, но не закрыто
      ↓ закрытие периода
payroll_entries                                   ← начислено за период
      ↓ выплата
salary_payments → cash_transactions               ← реально выданы деньги
```

Разделение начисления и выплаты обязательно: в цехе платят авансами в середине месяца и остаток в конце. `payroll_entries.advance_paid` собирает авансы, `to_pay = total_accrued − advance_paid`.

Защита от двойной оплаты — `work_logs.payroll_entry_id`. При закрытии периода берутся только записи с `payroll_entry_id IS NULL`, и им проставляется ссылка. Повторное закрытие того же периода физически не сможет захватить те же строки.

```sql
-- Расчёт начислений при закрытии периода
SELECT employee_id, SUM(amount) AS work_amount, SUM(quantity) AS units
FROM work_logs
WHERE company_id = $1
  AND status = 'APPROVED'
  AND payroll_entry_id IS NULL
  AND work_date BETWEEN $2 AND $3
GROUP BY employee_id;
```

Этот запрос покрывается индексом `idx_work_logs_unpaid` (partial, только незакрытые) — он остаётся крошечным независимо от того, сколько лет истории накопилось.

### 4.6 Номера документов: `company_counters`

Владельцу нужен «Заказ №14», а не UUID. Автоинкремент не годится — номера должны быть свои у каждой компании и без дыр.

```ts
const [counter] = await tx.$queryRaw<{ last_value: number }[]>`
  INSERT INTO company_counters (company_id, entity, last_value)
  VALUES (${companyId}::uuid, 'order', 1)
  ON CONFLICT (company_id, entity)
  DO UPDATE SET last_value = company_counters.last_value + 1
  RETURNING last_value
`;
```

`INSERT ... ON CONFLICT DO UPDATE ... RETURNING` — атомарно, одним запросом, без явной блокировки. Строка счётчика блокируется до конца транзакции, параллельные заказы встают в очередь — при паре заказов в минуту это ничего не стоит.

### 4.7 Telegram

- `employees.telegram_user_id BIGINT UNIQUE` — идентификатор Telegram не влезает в `int4`, и один аккаунт не может быть двумя рабочими.
- `telegram_link_codes` — одноразовые коды привязки с TTL.
- `telegram_updates(update_id PK)` — идемпотентность. Telegram ретраит вебхук при таймауте; без этой таблицы один отчёт «24 пары» записался бы дважды. Вставка `update_id` — первое, что делает обработчик; конфликт означает «уже обработали, выходим».
- `employees.default_operation_id` — если у рабочего одна специализация, бот пропускает шаг выбора операции. Мелочь, которая заметно ускоряет ежедневный сценарий.

---

## 5. Индексы: что и зачем

Полный список — в `schema.prisma` (`@@index`) и `002_constraints.sql` (partial/covering). Логика такая:

**Составные, всегда от `company_id`.** Одиночный индекс по `company_id` бесполезен — селективность нулевая внутри одной компании. Работают только `(company_id, <дата или статус>)`.

**Сортировка в индексе.** `@@index([companyId, soldAt(sort: Desc)])` — списки всегда идут «новые сверху», индекс с `DESC` отдаёт их без шага сортировки.

**Partial-индексы для «горячих» подмножеств.** Именно они дают системе способность не тормозить со временем:

| Индекс | Размер через 3 года |
|---|---|
| `idx_orders_active` (только активные заказы) | десятки строк |
| `idx_work_logs_pending` (только неподтверждённые) | единицы строк |
| `idx_work_logs_unpaid` (только незакрытая выработка) | сотни строк |
| `idx_products_low_stock` | единицы строк |

Крон уведомлений раз в час бегает по `idx_products_low_stock` и `idx_orders_active` — обе выборки читают буквально несколько страниц, независимо от объёма истории.

**Covering-индексы (`INCLUDE`) для аналитики.** `idx_sale_items_analytics` содержит `quantity, total, cost_price_snapshot`, поэтому «топ-10 товаров за месяц» выполняется как Index Only Scan — таблица `sale_items` вообще не читается.

**Чего сознательно НЕ делаем в MVP:**
- партиционирования (нужно от миллионов строк, у цеха их не будет годами);
- материализованных представлений (заготовка лежит закомментированной в `002_constraints.sql` — включим, когда дашборд станет медленнее 200 мс);
- полнотекстового поиска (`ILIKE` по индексу `(company_id, name)` хватает на тысячи товаров).

Преждевременная оптимизация здесь дороже, чем перевод на неё потом: и MV, и партиционирование добавляются миграцией без изменения кода приложения.

---

## 6. Как считается аналитика

**Прибыль** = выручка − себестоимость проданного − расходы − выплаченная зарплата.

```sql
-- Дашборд владельца за период: один запрос вместо пяти
WITH period AS (SELECT $2::date AS d_from, $3::date AS d_to)
SELECT
  (SELECT COALESCE(sum(total_amount), 0) FROM sales, period
     WHERE company_id = $1 AND sold_at::date BETWEEN d_from AND d_to)     AS revenue,
  (SELECT COALESCE(sum(total_cost), 0) FROM sales, period
     WHERE company_id = $1 AND sold_at::date BETWEEN d_from AND d_to)     AS cogs,
  (SELECT COALESCE(sum(amount), 0) FROM expenses, period
     WHERE company_id = $1 AND spent_at BETWEEN d_from AND d_to)          AS expenses,
  (SELECT COALESCE(sum(amount), 0) FROM salary_payments, period
     WHERE company_id = $1 AND paid_at BETWEEN d_from AND d_to)           AS salaries,
  (SELECT COALESCE(sum(quantity), 0) FROM work_logs, period
     WHERE company_id = $1 AND status = 'APPROVED'
       AND work_date BETWEEN d_from AND d_to)                             AS units_produced;
```

Каждый подзапрос бьёт в свой индекс `(company_id, <дата>)`. `sales.total_cost` — та самая денормализация: без неё пришлось бы джойнить `sale_items` и суммировать снимки себестоимости.

**Топ-товары:**

```sql
SELECT p.id, p.name, p.sku,
       sum(si.quantity)                                  AS units_sold,
       sum(si.total)                                     AS revenue,
       sum(si.total - si.cost_price_snapshot * si.quantity) AS gross_profit
FROM sale_items si
JOIN sales   s ON s.id = si.sale_id
JOIN products p ON p.id = si.product_id
WHERE s.company_id = $1 AND s.sold_at >= $2
GROUP BY p.id, p.name, p.sku
ORDER BY revenue DESC
LIMIT 10;
```

**Важно:** зарплата в прибыль входит по **выплатам** (`salary_payments.paid_at`), а не по начислениям. Владелец мыслит кассовым методом: «сколько денег ушло в этом месяце». Начисления показываем отдельной строкой «долг по зарплате» = `SUM(payroll_entries.to_pay WHERE NOT is_paid)`.

---

## 7. Осознанные упрощения MVP и путь развития

| Упрощение | Почему сейчас | Как расширить потом |
|---|---|---|
| Нет размерной сетки (модель = товар) | цех делает партиями по моделям, размерный учёт удваивает сложность склада и заказов | добавить `product_variants(product_id, size)`, перенести `stock_quantity` туда; `stock_movements` уже спроектированы под замену `product_id` на `variant_id` одной миграцией |
| Нет склада сырья и списания материалов | материалы закупаются мешками и считаются в расходах; попытка вести их поштучно в MVP провалится на вводе данных | `materials` уже есть — добавить `material_stock_movements` по образцу товарного журнала |
| Нет незавершённого производства (WIP) | статуса заказа и `order_items.produced_quantity` достаточно для контроля | отдельная таблица стадий с остатками по операциям |
| Один склад | у цеха одна кладовая | `warehouse_id` в `stock_movements` и `products_stock(product_id, warehouse_id, qty)` |
| Нет мультивалютности | UZS | `currency` в `companies` уже заложена; курсы — отдельная таблица |
| `payroll` только сдельный | это основная модель оплаты в цехе | добавить `employees.salary_type (PIECE\|FIXED\|MIXED)` и `fixed_salary`, в расчёт добавить слагаемое |

Все перечисленные расширения — аддитивные миграции: ни одно не требует переписывать существующие таблицы или терять данные. Это и было главным критерием при проектировании.

---

## 8. Порядок применения

```bash
cd backend
cp .env.example .env                 # DATABASE_URL=postgresql://...

npx prisma migrate dev -n init       # создаст таблицы из schema.prisma

# constraints/индексы/триггер отдельной миграцией
npx prisma migrate dev --create-only -n constraints
cat prisma/sql/002_constraints.sql >> prisma/migrations/*_constraints/migration.sql
npx prisma migrate dev

npx prisma db seed                   # демо-компания, категории расходов, касса
```

Seed при регистрации компании обязан создать: кассу «Основная» (`is_default`), системные категории расходов (аренда, коммуналка, материалы, транспорт, прочее) и базовые операции (раскрой, пошив, затяжка, упаковка). Без этого первый экран приложения будет пустым, и владелец не поймёт, с чего начать.
