import { PaymentMethod } from '@prisma/client';
import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const saleItemSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().positive('validation.positive'),
  unitPrice: money,
});

export const createSaleSchema = z
  .object({
    customerId: z.string().uuid().optional(),
    orderId: z.string().uuid().optional(),
    soldAt: z.string().datetime().optional(),
    paymentMethod: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH),
    cashAccountId: z.string().uuid().optional(),
    discount: money.default('0'),
    paidAmount: money.optional(),
    note: z.string().trim().max(255).optional(),
    items: z.array(saleItemSchema).min(1, 'validation.items_required'),
  })
  .refine((v) => v.paymentMethod === PaymentMethod.DEBT || Boolean(v.cashAccountId), {
    message: 'validation.cash_account_required',
    path: ['cashAccountId'],
  });

export const listSalesSchema = z.object({
  customerId: z.string().uuid().optional(),
  paymentMethod: z.nativeEnum(PaymentMethod).optional(),
  dateFrom: isoDate.optional(),
  dateTo: isoDate.optional(),
  /** По умолчанию сторнированные не показываем — они не выручка. */
  includeCancelled: z.coerce.boolean().default(false),
});

export const cancelSaleSchema = z.object({
  reason: z.string().trim().max(255).optional(),
});

export type SaleItemDto = z.infer<typeof saleItemSchema>;
export type CreateSaleDto = z.infer<typeof createSaleSchema>;
export type ListSalesDto = z.infer<typeof listSalesSchema>;
export type CancelSaleDto = z.infer<typeof cancelSaleSchema>;
