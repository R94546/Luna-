-- CreateEnum
CREATE TYPE "UserRole" AS ENUM ('SUPERADMIN', 'OWNER', 'ADMIN', 'ACCOUNTANT');

-- CreateEnum
CREATE TYPE "CompanyPlan" AS ENUM ('TRIAL', 'BASIC', 'PRO');

-- CreateEnum
CREATE TYPE "CompanyStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "WorkLogStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "WorkLogSource" AS ENUM ('TELEGRAM', 'MANUAL');

-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('NEW', 'IN_PROGRESS', 'READY', 'ISSUED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PayrollPeriodStatus" AS ENUM ('OPEN', 'CLOSED', 'PAID');

-- CreateEnum
CREATE TYPE "SalaryPaymentType" AS ENUM ('ADVANCE', 'SALARY', 'BONUS');

-- CreateEnum
CREATE TYPE "StockMovementType" AS ENUM ('PRODUCTION_IN', 'PURCHASE_IN', 'RETURN_IN', 'SALE_OUT', 'ORDER_OUT', 'WRITE_OFF', 'ADJUSTMENT');

-- CreateEnum
CREATE TYPE "CashDirection" AS ENUM ('IN', 'OUT');

-- CreateEnum
CREATE TYPE "CashCategory" AS ENUM ('SALE', 'EXPENSE', 'SALARY', 'INVESTMENT', 'WITHDRAWAL', 'TRANSFER', 'OTHER');

-- CreateEnum
CREATE TYPE "CashAccountType" AS ENUM ('CASH', 'CARD', 'BANK');

-- CreateEnum
CREATE TYPE "PaymentMethod" AS ENUM ('CASH', 'CARD', 'TRANSFER', 'DEBT');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('LOW_STOCK', 'ORDER_OVERDUE', 'WORK_LOG_PENDING', 'WORK_LOG_ANOMALY', 'PAYROLL_READY', 'SYSTEM');

-- CreateTable
CREATE TABLE "companies" (
    "id" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "slug" VARCHAR(64) NOT NULL,
    "phone" VARCHAR(20),
    "address" VARCHAR(255),
    "currency" VARCHAR(3) NOT NULL DEFAULT 'UZS',
    "timezone" VARCHAR(64) NOT NULL DEFAULT 'Asia/Tashkent',
    "plan" "CompanyPlan" NOT NULL DEFAULT 'TRIAL',
    "status" "CompanyStatus" NOT NULL DEFAULT 'ACTIVE',
    "subscription_ends_at" TIMESTAMPTZ(3),
    "work_log_auto_approve" BOOLEAN NOT NULL DEFAULT false,
    "default_margin_pct" DECIMAL(5,2) NOT NULL DEFAULT 30,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "companies_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "company_counters" (
    "company_id" UUID NOT NULL,
    "entity" VARCHAR(32) NOT NULL,
    "last_value" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "company_counters_pkey" PRIMARY KEY ("company_id","entity")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "company_id" UUID,
    "phone" VARCHAR(20) NOT NULL,
    "email" VARCHAR(160),
    "password_hash" VARCHAR(255) NOT NULL,
    "full_name" VARCHAR(160) NOT NULL,
    "role" "UserRole" NOT NULL DEFAULT 'OWNER',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "last_login_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" VARCHAR(64) NOT NULL,
    "family_id" UUID NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "revoked_at" TIMESTAMPTZ(3),
    "user_agent" VARCHAR(255),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "push_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token" VARCHAR(255) NOT NULL,
    "platform" VARCHAR(16) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "push_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "employees" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "full_name" VARCHAR(160) NOT NULL,
    "phone" VARCHAR(20),
    "position" VARCHAR(80),
    "default_operation_id" UUID,
    "telegram_user_id" BIGINT,
    "telegram_username" VARCHAR(64),
    "telegram_linked_at" TIMESTAMPTZ(3),
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "hired_at" DATE,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "employees_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "telegram_link_codes" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "employee_id" UUID NOT NULL,
    "code" VARCHAR(12) NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "used_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "telegram_link_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "telegram_updates" (
    "update_id" BIGINT NOT NULL,
    "processed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "telegram_updates_pkey" PRIMARY KEY ("update_id")
);

-- CreateTable
CREATE TABLE "operations" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "code" VARCHAR(32),
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "operations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "piece_rates" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "operation_id" UUID NOT NULL,
    "product_id" UUID,
    "employee_id" UUID,
    "rate" DECIMAL(14,2) NOT NULL,
    "valid_from" DATE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "valid_to" DATE,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "piece_rates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "products" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sku" VARCHAR(48) NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "category" VARCHAR(80),
    "photo_url" VARCHAR(512),
    "sale_price" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "cost_price" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "stock_quantity" INTEGER NOT NULL DEFAULT 0,
    "min_stock_level" INTEGER NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "stock_movements" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "type" "StockMovementType" NOT NULL,
    "quantity" INTEGER NOT NULL,
    "balance_after" INTEGER NOT NULL,
    "ref_type" VARCHAR(24),
    "ref_id" UUID,
    "note" VARCHAR(255),
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stock_movements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "employee_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "operation_id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "rate" DECIMAL(14,2) NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "work_date" DATE NOT NULL,
    "status" "WorkLogStatus" NOT NULL DEFAULT 'PENDING',
    "source" "WorkLogSource" NOT NULL DEFAULT 'TELEGRAM',
    "note" VARCHAR(255),
    "reject_reason" VARCHAR(255),
    "telegram_msg_id" BIGINT,
    "approved_by_id" UUID,
    "approved_at" TIMESTAMPTZ(3),
    "payroll_entry_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "work_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payroll_periods" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "period_start" DATE NOT NULL,
    "period_end" DATE NOT NULL,
    "status" "PayrollPeriodStatus" NOT NULL DEFAULT 'OPEN',
    "total_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "closed_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payroll_periods_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payroll_entries" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "period_id" UUID NOT NULL,
    "employee_id" UUID NOT NULL,
    "work_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "bonus" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "deduction" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "advance_paid" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "total_accrued" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "to_pay" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "is_paid" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "payroll_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "salary_payments" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "employee_id" UUID NOT NULL,
    "payroll_entry_id" UUID,
    "type" "SalaryPaymentType" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "paid_at" DATE NOT NULL,
    "note" VARCHAR(255),
    "cash_transaction_id" UUID,
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "salary_payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "customers" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" VARCHAR(160) NOT NULL,
    "phone" VARCHAR(20),
    "note" VARCHAR(255),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "customers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "orders" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "order_number" INTEGER NOT NULL,
    "customer_id" UUID,
    "status" "OrderStatus" NOT NULL DEFAULT 'NEW',
    "due_date" DATE,
    "issued_at" TIMESTAMPTZ(3),
    "total_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "prepaid_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "note" VARCHAR(500),
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "order_items" (
    "id" UUID NOT NULL,
    "order_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "produced_quantity" INTEGER NOT NULL DEFAULT 0,
    "unitPrice" DECIMAL(14,2) NOT NULL,
    "total" DECIMAL(14,2) NOT NULL,

    CONSTRAINT "order_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sales" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sale_number" INTEGER NOT NULL,
    "customer_id" UUID,
    "order_id" UUID,
    "total_amount" DECIMAL(14,2) NOT NULL,
    "discount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "paid_amount" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "total_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "payment_method" "PaymentMethod" NOT NULL DEFAULT 'CASH',
    "sold_at" TIMESTAMPTZ(3) NOT NULL,
    "note" VARCHAR(255),
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sales_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sale_items" (
    "id" UUID NOT NULL,
    "sale_id" UUID NOT NULL,
    "product_id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unit_price" DECIMAL(14,2) NOT NULL,
    "cost_price_snapshot" DECIMAL(14,2) NOT NULL,
    "total" DECIMAL(14,2) NOT NULL,

    CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cash_accounts" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "type" "CashAccountType" NOT NULL DEFAULT 'CASH',
    "balance" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "is_default" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cash_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cash_transactions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "account_id" UUID NOT NULL,
    "direction" "CashDirection" NOT NULL,
    "category" "CashCategory" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "ref_type" VARCHAR(24),
    "ref_id" UUID,
    "sale_id" UUID,
    "occurred_at" TIMESTAMPTZ(3) NOT NULL,
    "note" VARCHAR(255),
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cash_transactions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "expense_categories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" VARCHAR(80) NOT NULL,
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "color" VARCHAR(9),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "expense_categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "expenses" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "spent_at" DATE NOT NULL,
    "note" VARCHAR(255),
    "cash_transaction_id" UUID,
    "created_by_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "expenses_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "materials" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" VARCHAR(120) NOT NULL,
    "unit" VARCHAR(16) NOT NULL,
    "unit_price" DECIMAL(14,2) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "materials_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cost_calculations" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "product_id" UUID,
    "name" VARCHAR(160) NOT NULL,
    "materials_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "labor_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "overhead_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "time_minutes" INTEGER NOT NULL DEFAULT 0,
    "total_cost" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "margin_percent" DECIMAL(5,2) NOT NULL DEFAULT 30,
    "recommended_price" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "profit_per_unit" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "is_applied" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "cost_calculations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cost_calculation_items" (
    "id" UUID NOT NULL,
    "calculation_id" UUID NOT NULL,
    "material_id" UUID,
    "name" VARCHAR(120) NOT NULL,
    "unit" VARCHAR(16) NOT NULL,
    "quantity" DECIMAL(12,3) NOT NULL,
    "unit_price" DECIMAL(14,2) NOT NULL,
    "total" DECIMAL(14,2) NOT NULL,

    CONSTRAINT "cost_calculation_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID,
    "type" "NotificationType" NOT NULL,
    "title" VARCHAR(160) NOT NULL,
    "body" VARCHAR(500) NOT NULL,
    "payload" JSONB,
    "is_read" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID,
    "action" VARCHAR(48) NOT NULL,
    "entity" VARCHAR(48) NOT NULL,
    "entity_id" UUID,
    "changes" JSONB,
    "ip" VARCHAR(45),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "companies_slug_key" ON "companies"("slug");

-- CreateIndex
CREATE INDEX "companies_status_idx" ON "companies"("status");

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");

-- CreateIndex
CREATE INDEX "users_company_id_role_idx" ON "users"("company_id", "role");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_expires_at_idx" ON "refresh_tokens"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "push_tokens_token_key" ON "push_tokens"("token");

-- CreateIndex
CREATE INDEX "push_tokens_user_id_idx" ON "push_tokens"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "employees_telegram_user_id_key" ON "employees"("telegram_user_id");

-- CreateIndex
CREATE INDEX "employees_company_id_is_active_idx" ON "employees"("company_id", "is_active");

-- CreateIndex
CREATE UNIQUE INDEX "telegram_link_codes_code_key" ON "telegram_link_codes"("code");

-- CreateIndex
CREATE INDEX "telegram_link_codes_employee_id_idx" ON "telegram_link_codes"("employee_id");

-- CreateIndex
CREATE INDEX "telegram_updates_processed_at_idx" ON "telegram_updates"("processed_at");

-- CreateIndex
CREATE INDEX "operations_company_id_is_active_idx" ON "operations"("company_id", "is_active");

-- CreateIndex
CREATE UNIQUE INDEX "operations_company_id_name_key" ON "operations"("company_id", "name");

-- CreateIndex
CREATE INDEX "piece_rates_company_id_operation_id_product_id_employee_id_idx" ON "piece_rates"("company_id", "operation_id", "product_id", "employee_id");

-- CreateIndex
CREATE INDEX "products_company_id_is_active_idx" ON "products"("company_id", "is_active");

-- CreateIndex
CREATE UNIQUE INDEX "products_company_id_sku_key" ON "products"("company_id", "sku");

-- CreateIndex
CREATE INDEX "stock_movements_company_id_product_id_created_at_idx" ON "stock_movements"("company_id", "product_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "stock_movements_company_id_created_at_idx" ON "stock_movements"("company_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "stock_movements_ref_type_ref_id_idx" ON "stock_movements"("ref_type", "ref_id");

-- CreateIndex
CREATE INDEX "work_logs_company_id_work_date_idx" ON "work_logs"("company_id", "work_date" DESC);

-- CreateIndex
CREATE INDEX "work_logs_company_id_employee_id_work_date_idx" ON "work_logs"("company_id", "employee_id", "work_date" DESC);

-- CreateIndex
CREATE INDEX "work_logs_company_id_status_idx" ON "work_logs"("company_id", "status");

-- CreateIndex
CREATE INDEX "work_logs_company_id_product_id_work_date_idx" ON "work_logs"("company_id", "product_id", "work_date");

-- CreateIndex
CREATE INDEX "work_logs_payroll_entry_id_idx" ON "work_logs"("payroll_entry_id");

-- CreateIndex
CREATE INDEX "payroll_periods_company_id_status_idx" ON "payroll_periods"("company_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "payroll_periods_company_id_period_start_period_end_key" ON "payroll_periods"("company_id", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "payroll_entries_company_id_employee_id_idx" ON "payroll_entries"("company_id", "employee_id");

-- CreateIndex
CREATE UNIQUE INDEX "payroll_entries_period_id_employee_id_key" ON "payroll_entries"("period_id", "employee_id");

-- CreateIndex
CREATE UNIQUE INDEX "salary_payments_cash_transaction_id_key" ON "salary_payments"("cash_transaction_id");

-- CreateIndex
CREATE INDEX "salary_payments_company_id_employee_id_paid_at_idx" ON "salary_payments"("company_id", "employee_id", "paid_at" DESC);

-- CreateIndex
CREATE INDEX "salary_payments_company_id_paid_at_idx" ON "salary_payments"("company_id", "paid_at" DESC);

-- CreateIndex
CREATE INDEX "customers_company_id_name_idx" ON "customers"("company_id", "name");

-- CreateIndex
CREATE INDEX "orders_company_id_status_due_date_idx" ON "orders"("company_id", "status", "due_date");

-- CreateIndex
CREATE INDEX "orders_company_id_created_at_idx" ON "orders"("company_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "orders_company_id_customer_id_idx" ON "orders"("company_id", "customer_id");

-- CreateIndex
CREATE UNIQUE INDEX "orders_company_id_order_number_key" ON "orders"("company_id", "order_number");

-- CreateIndex
CREATE INDEX "order_items_order_id_idx" ON "order_items"("order_id");

-- CreateIndex
CREATE INDEX "order_items_product_id_idx" ON "order_items"("product_id");

-- CreateIndex
CREATE INDEX "sales_company_id_sold_at_idx" ON "sales"("company_id", "sold_at" DESC);

-- CreateIndex
CREATE INDEX "sales_company_id_customer_id_idx" ON "sales"("company_id", "customer_id");

-- CreateIndex
CREATE UNIQUE INDEX "sales_company_id_sale_number_key" ON "sales"("company_id", "sale_number");

-- CreateIndex
CREATE INDEX "sale_items_sale_id_idx" ON "sale_items"("sale_id");

-- CreateIndex
CREATE INDEX "sale_items_product_id_idx" ON "sale_items"("product_id");

-- CreateIndex
CREATE UNIQUE INDEX "cash_accounts_company_id_name_key" ON "cash_accounts"("company_id", "name");

-- CreateIndex
CREATE INDEX "cash_transactions_company_id_occurred_at_idx" ON "cash_transactions"("company_id", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "cash_transactions_company_id_category_occurred_at_idx" ON "cash_transactions"("company_id", "category", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "cash_transactions_account_id_occurred_at_idx" ON "cash_transactions"("account_id", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "cash_transactions_ref_type_ref_id_idx" ON "cash_transactions"("ref_type", "ref_id");

-- CreateIndex
CREATE UNIQUE INDEX "expense_categories_company_id_name_key" ON "expense_categories"("company_id", "name");

-- CreateIndex
CREATE UNIQUE INDEX "expenses_cash_transaction_id_key" ON "expenses"("cash_transaction_id");

-- CreateIndex
CREATE INDEX "expenses_company_id_spent_at_idx" ON "expenses"("company_id", "spent_at" DESC);

-- CreateIndex
CREATE INDEX "expenses_company_id_category_id_spent_at_idx" ON "expenses"("company_id", "category_id", "spent_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "materials_company_id_name_key" ON "materials"("company_id", "name");

-- CreateIndex
CREATE INDEX "cost_calculations_company_id_product_id_idx" ON "cost_calculations"("company_id", "product_id");

-- CreateIndex
CREATE INDEX "cost_calculation_items_calculation_id_idx" ON "cost_calculation_items"("calculation_id");

-- CreateIndex
CREATE INDEX "notifications_company_id_is_read_created_at_idx" ON "notifications"("company_id", "is_read", "created_at" DESC);

-- CreateIndex
CREATE INDEX "notifications_user_id_is_read_idx" ON "notifications"("user_id", "is_read");

-- CreateIndex
CREATE INDEX "audit_logs_company_id_created_at_idx" ON "audit_logs"("company_id", "created_at" DESC);

-- CreateIndex
CREATE INDEX "audit_logs_company_id_entity_entity_id_idx" ON "audit_logs"("company_id", "entity", "entity_id");

-- AddForeignKey
ALTER TABLE "company_counters" ADD CONSTRAINT "company_counters_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "push_tokens" ADD CONSTRAINT "push_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employees" ADD CONSTRAINT "employees_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employees" ADD CONSTRAINT "employees_default_operation_id_fkey" FOREIGN KEY ("default_operation_id") REFERENCES "operations"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "telegram_link_codes" ADD CONSTRAINT "telegram_link_codes_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "telegram_link_codes" ADD CONSTRAINT "telegram_link_codes_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employees"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "operations" ADD CONSTRAINT "operations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "piece_rates" ADD CONSTRAINT "piece_rates_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "piece_rates" ADD CONSTRAINT "piece_rates_operation_id_fkey" FOREIGN KEY ("operation_id") REFERENCES "operations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "piece_rates" ADD CONSTRAINT "piece_rates_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "piece_rates" ADD CONSTRAINT "piece_rates_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employees"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_movements" ADD CONSTRAINT "stock_movements_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employees"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_operation_id_fkey" FOREIGN KEY ("operation_id") REFERENCES "operations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_approved_by_id_fkey" FOREIGN KEY ("approved_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_logs" ADD CONSTRAINT "work_logs_payroll_entry_id_fkey" FOREIGN KEY ("payroll_entry_id") REFERENCES "payroll_entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_periods" ADD CONSTRAINT "payroll_periods_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_entries" ADD CONSTRAINT "payroll_entries_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_entries" ADD CONSTRAINT "payroll_entries_period_id_fkey" FOREIGN KEY ("period_id") REFERENCES "payroll_periods"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_entries" ADD CONSTRAINT "payroll_entries_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employees"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salary_payments" ADD CONSTRAINT "salary_payments_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salary_payments" ADD CONSTRAINT "salary_payments_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "employees"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salary_payments" ADD CONSTRAINT "salary_payments_payroll_entry_id_fkey" FOREIGN KEY ("payroll_entry_id") REFERENCES "payroll_entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salary_payments" ADD CONSTRAINT "salary_payments_cash_transaction_id_fkey" FOREIGN KEY ("cash_transaction_id") REFERENCES "cash_transactions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salary_payments" ADD CONSTRAINT "salary_payments_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "customers" ADD CONSTRAINT "customers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "order_items" ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_accounts" ADD CONSTRAINT "cash_accounts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_transactions" ADD CONSTRAINT "cash_transactions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_transactions" ADD CONSTRAINT "cash_transactions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "cash_accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_transactions" ADD CONSTRAINT "cash_transactions_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_transactions" ADD CONSTRAINT "cash_transactions_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expense_categories" ADD CONSTRAINT "expense_categories_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "expense_categories"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_cash_transaction_id_fkey" FOREIGN KEY ("cash_transaction_id") REFERENCES "cash_transactions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "materials" ADD CONSTRAINT "materials_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cost_calculations" ADD CONSTRAINT "cost_calculations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cost_calculations" ADD CONSTRAINT "cost_calculations_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cost_calculation_items" ADD CONSTRAINT "cost_calculation_items_calculation_id_fkey" FOREIGN KEY ("calculation_id") REFERENCES "cost_calculations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cost_calculation_items" ADD CONSTRAINT "cost_calculation_items_material_id_fkey" FOREIGN KEY ("material_id") REFERENCES "materials"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
