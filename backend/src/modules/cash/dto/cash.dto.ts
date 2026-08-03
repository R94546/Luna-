import { CashAccountType, CashCategory, CashDirection } from '@prisma/client';
import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v) && Number(v) > 0, {
    message: 'validation.positive',
  });

export const createAccountSchema = z.object({
  name: z.string().trim().min(2, 'validation.required').max(80),
  type: z.nativeEnum(CashAccountType).default(CashAccountType.CASH),
  /** Стартовый остаток: в кассе уже лежат деньги на момент заведения. */
  balance: money.optional(),
  isDefault: z.boolean().default(false),
});

/**
 * Категории, доступные для ручной операции.
 *
 * SALE, SALARY и EXPENSE сюда не входят намеренно: у каждой из них есть
 * собственный путь (`/sales`, `/salary-payments`, `/expenses`), который
 * заводит и первичный документ, и движение по кассе одной транзакцией.
 * Разреши их здесь — и появится возможность записать зарплату в кассу,
 * не создав выплату, то есть развести ведомость с деньгами.
 */
export const MANUAL_CATEGORIES = [
  CashCategory.INVESTMENT,
  CashCategory.WITHDRAWAL,
  CashCategory.TRANSFER,
  CashCategory.OTHER,
] as const;

export const createTransactionSchema = z.object({
  accountId: z.string().uuid(),
  direction: z.nativeEnum(CashDirection),
  category: z.enum(MANUAL_CATEGORIES, {
    errorMap: () => ({ message: 'validation.category_not_manual' }),
  }),
  amount: money,
  occurredAt: isoDate,
  note: z.string().trim().max(255).optional(),
});

export const listTransactionsSchema = z.object({
  accountId: z.string().uuid().optional(),
  direction: z.nativeEnum(CashDirection).optional(),
  category: z.nativeEnum(CashCategory).optional(),
  dateFrom: isoDate.optional(),
  dateTo: isoDate.optional(),
});

export const summarySchema = z
  .object({
    dateFrom: isoDate,
    dateTo: isoDate,
  })
  .refine((v) => v.dateFrom <= v.dateTo, {
    message: 'validation.period_order',
    path: ['dateTo'],
  });

export type CreateAccountDto = z.infer<typeof createAccountSchema>;
export type CreateTransactionDto = z.infer<typeof createTransactionSchema>;
export type ListTransactionsDto = z.infer<typeof listTransactionsSchema>;
export type SummaryDto = z.infer<typeof summarySchema>;
