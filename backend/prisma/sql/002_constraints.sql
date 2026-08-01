-- Luna — то, что Prisma не умеет описать в schema.prisma.
-- Применяется как отдельная миграция после `prisma migrate dev`:
--   npx prisma migrate dev --create-only -n constraints
--   cat prisma/sql/002_constraints.sql >> prisma/migrations/<ts>_constraints/migration.sql
--   npx prisma migrate dev

-- ============================================================
-- 1. CHECK-констрейнты: инварианты, которые нельзя нарушить даже багом в коде
-- ============================================================

ALTER TABLE work_logs
  ADD CONSTRAINT work_logs_quantity_positive CHECK (quantity > 0),
  ADD CONSTRAINT work_logs_rate_non_negative CHECK (rate >= 0),
  ADD CONSTRAINT work_logs_amount_matches CHECK (amount = quantity * rate);

ALTER TABLE piece_rates
  ADD CONSTRAINT piece_rates_rate_non_negative CHECK (rate >= 0),
  ADD CONSTRAINT piece_rates_valid_range CHECK (valid_to IS NULL OR valid_to >= valid_from);

ALTER TABLE products
  ADD CONSTRAINT products_stock_non_negative CHECK (stock_quantity >= 0),
  ADD CONSTRAINT products_prices_non_negative CHECK (sale_price >= 0 AND cost_price >= 0);

ALTER TABLE order_items
  ADD CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
  ADD CONSTRAINT order_items_produced_within_bounds CHECK (produced_quantity >= 0);

ALTER TABLE sale_items
  ADD CONSTRAINT sale_items_quantity_positive CHECK (quantity > 0);

ALTER TABLE cash_transactions
  ADD CONSTRAINT cash_tx_amount_positive CHECK (amount > 0);
-- Знак определяется полем direction, а не знаком суммы. Так проще агрегировать
-- и невозможно случайно записать отрицательный приход.

ALTER TABLE expenses
  ADD CONSTRAINT expenses_amount_positive CHECK (amount > 0);

ALTER TABLE salary_payments
  ADD CONSTRAINT salary_payments_amount_positive CHECK (amount > 0);

ALTER TABLE stock_movements
  ADD CONSTRAINT stock_movements_quantity_not_zero CHECK (quantity <> 0);

ALTER TABLE payroll_periods
  ADD CONSTRAINT payroll_periods_range CHECK (period_end >= period_start);

-- ============================================================
-- 2. Частичные (partial) индексы — Prisma их не генерирует
-- ============================================================

-- Активные заказы: дашборд и проверка просрочки бегают только по ним.
-- В цехе на 10 000 исторических заказов активных всегда десятки.
CREATE INDEX idx_orders_active
  ON orders (company_id, due_date)
  WHERE status IN ('NEW', 'IN_PROGRESS', 'READY');

-- Очередь на подтверждение выработки — самый частый запрос админа.
CREATE INDEX idx_work_logs_pending
  ON work_logs (company_id, created_at DESC)
  WHERE status = 'PENDING';

-- Незакрытая выработка: то, что попадёт в следующий зарплатный период.
CREATE INDEX idx_work_logs_unpaid
  ON work_logs (company_id, employee_id, work_date)
  WHERE status = 'APPROVED' AND payroll_entry_id IS NULL;

-- Товары ниже минимального остатка — для крона уведомлений.
CREATE INDEX idx_products_low_stock
  ON products (company_id)
  WHERE deleted_at IS NULL AND stock_quantity <= min_stock_level;

-- Живые справочники (мягкое удаление).
CREATE INDEX idx_products_alive   ON products   (company_id, name) WHERE deleted_at IS NULL;
CREATE INDEX idx_employees_alive  ON employees  (company_id, full_name) WHERE deleted_at IS NULL;
CREATE INDEX idx_customers_alive  ON customers  (company_id, name) WHERE deleted_at IS NULL;

-- Активные refresh-токены (чистка истёкших кроном).
CREATE INDEX idx_refresh_tokens_live
  ON refresh_tokens (user_id)
  WHERE revoked_at IS NULL;

-- Одна касса по умолчанию на компанию.
CREATE UNIQUE INDEX uq_cash_accounts_default
  ON cash_accounts (company_id)
  WHERE is_default;

-- Одна открытая расценка на комбинацию (последняя, без даты окончания).
CREATE UNIQUE INDEX uq_piece_rates_open
  ON piece_rates (company_id, operation_id, COALESCE(product_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(employee_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE valid_to IS NULL;

-- ============================================================
-- 3. Покрывающие индексы для аналитики
-- ============================================================

-- Топ-товары и выручка по периоду: индекс закрывает запрос целиком,
-- Postgres берёт данные из индекса без обращения к таблице (Index Only Scan).
CREATE INDEX idx_sale_items_analytics
  ON sale_items (product_id)
  INCLUDE (quantity, total, cost_price_snapshot);

-- Выработка по сотрудникам за период.
CREATE INDEX idx_work_logs_payroll_calc
  ON work_logs (company_id, employee_id, work_date)
  INCLUDE (amount, quantity)
  WHERE status = 'APPROVED';

-- ============================================================
-- 4. Триггер: аудит остатка склада
--    Гарантирует, что products.stock_quantity нельзя разойтись с журналом.
-- ============================================================

-- Инвариант: products.stock_quantity = сумма всех движений по товару.
-- Проверяем именно сумму, а не balance_after конкретной строки: в одной
-- транзакции по одному товару может быть несколько движений (продажа двух
-- позиций одной модели), и промежуточные balance_after с финальным остатком
-- совпадать не обязаны.
CREATE OR REPLACE FUNCTION check_stock_movement_balance() RETURNS trigger AS $$
DECLARE
  ledger_sum int;
  current_stock int;
BEGIN
  SELECT COALESCE(sum(quantity), 0) INTO ledger_sum
    FROM stock_movements WHERE product_id = NEW.product_id;
  SELECT stock_quantity INTO current_stock
    FROM products WHERE id = NEW.product_id;

  IF ledger_sum <> current_stock THEN
    RAISE EXCEPTION
      'Расхождение склада по товару %: журнал даёт %, в products %',
      NEW.product_id, ledger_sum, current_stock;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- CONSTRAINT TRIGGER DEFERRABLE: проверка в конце транзакции, когда
-- и движение, и обновление products уже записаны — порядок операций не важен.
-- Стоимость: агрегат по индексу (company_id, product_id, created_at) на каждую
-- вставку. На объёмах цеха это микросекунды. Если когда-нибудь станет узким
-- местом — снимаем триггер и переходим на ночную сверку.
CREATE CONSTRAINT TRIGGER trg_stock_movement_balance
  AFTER INSERT ON stock_movements
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION check_stock_movement_balance();

-- ============================================================
-- 5. Row Level Security — включать перед первым платящим клиентом
--    Страховка на случай бага в Prisma-middleware.
--    Приложение перед запросом выполняет:  SET LOCAL app.company_id = '<uuid>';
-- ============================================================

-- Раскомментировать при переходе на платную эксплуатацию:
--
-- DO $$
-- DECLARE t text;
-- BEGIN
--   FOREACH t IN ARRAY ARRAY[
--     'employees','operations','piece_rates','products','work_logs',
--     'payroll_periods','payroll_entries','salary_payments','customers',
--     'orders','sales','stock_movements','expense_categories','expenses',
--     'cash_accounts','cash_transactions','materials','cost_calculations',
--     'notifications','telegram_link_codes','audit_logs'
--   ] LOOP
--     EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
--     EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
--     EXECUTE format(
--       'CREATE POLICY tenant_isolation ON %I USING (company_id = current_setting(''app.company_id'', true)::uuid)', t);
--   END LOOP;
-- END $$;

-- ============================================================
-- 6. Материализованное представление дневной аналитики.
--    В MVP не нужно — запросы по индексам выше отрабатывают за миллисекунды.
--    Включаем, когда у компании появятся сотни тысяч строк продаж.
-- ============================================================

-- CREATE MATERIALIZED VIEW mv_daily_sales AS
-- SELECT s.company_id,
--        date_trunc('day', s.sold_at AT TIME ZONE 'Asia/Tashkent')::date AS day,
--        count(*)                                   AS sales_count,
--        sum(s.total_amount)                        AS revenue,
--        sum(s.total_cost)                          AS cost,
--        sum(s.total_amount - s.total_cost)         AS gross_profit
-- FROM sales s
-- GROUP BY 1, 2;
-- CREATE UNIQUE INDEX ON mv_daily_sales (company_id, day);
-- -- обновление: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
