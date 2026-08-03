import { OrderStatus, PaymentMethod } from '@prisma/client';
import { z } from 'zod';

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'validation.date_format');

const money = z
  .union([z.string(), z.number()])
  .transform((v) => String(v))
  .refine((v) => /^\d+(\.\d{1,2})?$/.test(v), { message: 'validation.positive' });

export const orderItemSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().positive('validation.positive'),
  unitPrice: money,
});

export const createOrderSchema = z.object({
  customerId: z.string().uuid().optional(),
  dueDate: isoDate.optional(),
  prepaidAmount: money.default('0'),
  note: z.string().trim().max(500).optional(),
  items: z.array(orderItemSchema).min(1, 'validation.items_required'),
});

export const updateOrderSchema = z
  .object({
    customerId: z.string().uuid().optional(),
    dueDate: isoDate.optional(),
    note: z.string().trim().max(500).optional(),
    items: z.array(orderItemSchema).min(1).optional(),
  })
  .refine((v) => Object.values(v).some((x) => x !== undefined), {
    message: 'validation.nothing_to_update',
  });

/** Отметка о произведённом: пришло столько-то пар по позиции заказа. */
export const updateProgressSchema = z.object({
  items: z
    .array(
      z.object({
        itemId: z.string().uuid(),
        producedQuantity: z.number().int().min(0),
      }),
    )
    .min(1),
});

export const changeStatusSchema = z
  .object({
    status: z.nativeEnum(OrderStatus),
    /** Только для перехода в ISSUED: оформить продажу вместе с выдачей. */
    createSale: z.boolean().default(false),
    cashAccountId: z.string().uuid().optional(),
    paidAmount: money.optional(),
    paymentMethod: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH),
    reason: z.string().trim().max(255).optional(),
  })
  .refine((v) => !v.createSale || v.status === OrderStatus.ISSUED, {
    message: 'validation.sale_only_on_issue',
    path: ['createSale'],
  })
  .refine(
    (v) => !v.createSale || v.paymentMethod === PaymentMethod.DEBT || Boolean(v.cashAccountId),
    { message: 'validation.cash_account_required', path: ['cashAccountId'] },
  );

export const listOrdersSchema = z.object({
  status: z.nativeEnum(OrderStatus).optional(),
  customerId: z.string().uuid().optional(),
  overdue: z.coerce.boolean().optional(),
});

export type CreateOrderDto = z.infer<typeof createOrderSchema>;
export type UpdateOrderDto = z.infer<typeof updateOrderSchema>;
export type UpdateProgressDto = z.infer<typeof updateProgressSchema>;
export type ChangeStatusDto = z.infer<typeof changeStatusSchema>;
export type ListOrdersDto = z.infer<typeof listOrdersSchema>;
