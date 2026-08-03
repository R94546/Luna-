/**
 * Заказы и продажи на живой БД.
 *
 * Проверяются связки, которых не видно из модульных тестов: продажа
 * одновременно двигает склад, кассу и фиксирует себестоимость, а выдача
 * заказа делает это же, не списав товар дважды. Ошибка в любой из них
 * обнаружилась бы только при инвентаризации.
 *
 * Скрипт заводит свои товар, клиента и кассу, убирает их за собой.
 *
 * Запуск:
 *   npm run test:sales
 */
import { OrderStatus, PaymentMethod } from '@prisma/client';
import { CashService } from '../src/modules/cash/cash.service';
import { OrdersService } from '../src/modules/orders/orders.service';
import { SalesService } from '../src/modules/sales/sales.service';
import { StockService } from '../src/modules/stock/stock.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const stock = new StockService(prisma);
const cash = new CashService(prisma);
const sales = new SalesService(prisma, stock, cash);
const orders = new OrdersService(prisma, stock, sales);

const MARKER = 'SALES-TEST';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
}

async function checkThrows(label: string, code: string, fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn();
    failed++;
    console.log(`  ❌ ${label}: ошибки не было, ожидался ${code}`);
  } catch (error) {
    const actual = (error as { code?: string }).code ?? String(error);
    const ok = actual === code;
    if (ok) passed++;
    else failed++;
    console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}`);
  }
}

async function stockOf(productId: string): Promise<number> {
  const product = await prisma.product.findFirstOrThrow({ where: { id: productId } });
  return product.stockQuantity;
}

async function balanceOf(accountId: string): Promise<string> {
  const account = await prisma.cashAccount.findFirstOrThrow({ where: { id: accountId } });
  return account.balance.toString();
}

async function main(): Promise<void> {
  const company = await prisma.company.findFirst({ where: { slug: 'luna-shoes' } });
  if (!company) {
    throw new Error('Компания luna-shoes не найдена — сначала выполните `npm run seed`.');
  }

  await runWithTenant({ companyId: company.id }, () => scenario(company.id));
}

async function scenario(companyId: string): Promise<void> {
  await cleanup(companyId);

  const product = await prisma.product.create({
    data: {
      companyId,
      sku: `${MARKER}-SKU`,
      name: `${MARKER} model`,
      salePrice: '450000',
      costPrice: '280000',
      stockQuantity: 100,
    },
  });

  const account = await prisma.cashAccount.create({
    data: { companyId, name: `${MARKER} kassa`, balance: '0' },
  });

  const customer = await prisma.customer.create({
    data: { companyId, name: `${MARKER} mijoz` },
  });

  // ── Продажа за наличные ────────────────────────────────────────────────
  console.log('\n=== Продажа ===');
  const sale = await sales.create({
    customerId: customer.id,
    paymentMethod: PaymentMethod.CASH,
    cashAccountId: account.id,
    discount: '0',
    items: [{ productId: product.id, quantity: 8, unitPrice: '450000' }],
  });

  check('сумма', sale.totalAmount, '3600000');
  check('себестоимость зафиксирована', sale.totalCost, '2240000');
  check('прибыль посчитана сервером', sale.grossProfit, '1360000');
  check('долга нет', sale.debt, '0');
  check('склад списан', await stockOf(product.id), 92);
  check('деньги в кассе', await balanceOf(account.id), '3600000');
  check('номер продажи выдан', typeof sale.saleNumber === 'number' && sale.saleNumber > 0, true);

  const saleTx = await prisma.cashTransaction.findFirst({ where: { saleId: sale.id } });
  check('движение по кассе категории SALE', saleTx?.category, 'SALE');

  /**
   * Себестоимость обязана остаться прежней после пересчёта калькулятора:
   * прибыль прошлого месяца не должна меняться задним числом.
   */
  console.log('\n=== Себестоимость не переписывается задним числом ===');
  await prisma.product.update({ where: { id: product.id }, data: { costPrice: '999999' } });
  const reread = await sales.findOne(sale.id);
  check('снимок сохранился', reread.totalCost, '2240000');
  check('прибыль не поехала', reread.grossProfit, '1360000');
  await prisma.product.update({ where: { id: product.id }, data: { costPrice: '280000' } });

  // ── Продажа в долг ─────────────────────────────────────────────────────
  console.log('\n=== Продажа в долг ===');
  const debtSale = await sales.create({
    customerId: customer.id,
    paymentMethod: PaymentMethod.DEBT,
    discount: '0',
    items: [{ productId: product.id, quantity: 2, unitPrice: '450000' }],
  });

  check('долг равен сумме', debtSale.debt, '900000');
  check('склад списан всё равно', await stockOf(product.id), 90);
  check('в кассу не попало', await balanceOf(account.id), '3600000');

  // ── Проверки на входе ──────────────────────────────────────────────────
  console.log('\n=== Отказы ===');
  await checkThrows('нехватка остатка', 'INSUFFICIENT_STOCK', () =>
    sales.create({
      paymentMethod: PaymentMethod.CASH,
      cashAccountId: account.id,
      discount: '0',
      items: [{ productId: product.id, quantity: 10_000, unitPrice: '450000' }],
    }),
  );
  check('склад не тронут после отказа', await stockOf(product.id), 90);

  await checkThrows('скидка больше суммы', 'DISCOUNT_TOO_LARGE', () =>
    sales.create({
      paymentMethod: PaymentMethod.CASH,
      cashAccountId: account.id,
      discount: '99999999',
      items: [{ productId: product.id, quantity: 1, unitPrice: '450000' }],
    }),
  );

  await checkThrows('оплачено больше суммы', 'PAID_EXCEEDS_TOTAL', () =>
    sales.create({
      paymentMethod: PaymentMethod.CASH,
      cashAccountId: account.id,
      discount: '0',
      paidAmount: '99999999',
      items: [{ productId: product.id, quantity: 1, unitPrice: '450000' }],
    }),
  );

  // ── Сторно ─────────────────────────────────────────────────────────────
  console.log('\n=== Сторно продажи ===');
  const cancelled = await sales.cancel(sale.id, 'oshibka');
  check('помечена сторнированной', cancelled.isCancelled, true);
  check('товар вернулся на склад', await stockOf(product.id), 98);
  check('деньги ушли из кассы', await balanceOf(account.id), '0');

  const stillThere = await prisma.sale.count({ where: { id: sale.id } });
  check('запись не удалена — история сохранена', stillThere, 1);

  const reversal = await prisma.cashTransaction.count({
    where: { saleId: sale.id, direction: 'OUT' },
  });
  check('обратная проводка создана', reversal, 1);

  await checkThrows('повторное сторно', 'SALE_ALREADY_CANCELLED', () => sales.cancel(sale.id));

  const listed = await sales.findAll({ page: 1, limit: 20, includeCancelled: false });
  check('сторнированная выпала из выручки', listed.items.some((s) => s.id === sale.id), false);

  // ── Заказ ──────────────────────────────────────────────────────────────
  console.log('\n=== Заказ ===');
  const order = await orders.create({
    customerId: customer.id,
    dueDate: '2019-12-31',
    prepaidAmount: '500000',
    items: [{ productId: product.id, quantity: 10, unitPrice: '450000' }],
  });

  check('номер выдан', typeof order.orderNumber === 'number' && order.orderNumber > 0, true);
  check('сумма', order.totalAmount, '4500000');
  check('долг за вычетом предоплаты', order.debt, '4000000');
  check('статус', order.status, 'NEW');
  check('доступные переходы', JSON.stringify(order.availableTransitions), '["IN_PROGRESS","CANCELLED"]');
  check('просрочен (срок в прошлом)', order.isOverdue, true);

  console.log('\n=== Прогресс ===');
  const withProgress = await orders.updateProgress(order.id, {
    items: [{ itemId: order.items[0].id, producedQuantity: 6 }],
  });
  check('процент считает сервер', withProgress.progress.percent, 60);

  console.log('\n=== Переходы статусов ===');
  await checkThrows('через шаг нельзя', 'INVALID_STATUS_TRANSITION', () =>
    orders.changeStatus(order.id, {
      status: OrderStatus.ISSUED,
      createSale: false,
      paymentMethod: PaymentMethod.CASH,
    }),
  );

  await orders.changeStatus(order.id, {
    status: OrderStatus.IN_PROGRESS,
    createSale: false,
    paymentMethod: PaymentMethod.CASH,
  });
  const ready = await orders.changeStatus(order.id, {
    status: OrderStatus.READY,
    createSale: false,
    paymentMethod: PaymentMethod.CASH,
  });
  check('дошёл до READY', ready.status, 'READY');

  await checkThrows('назад нельзя', 'INVALID_STATUS_TRANSITION', () =>
    orders.changeStatus(order.id, {
      status: OrderStatus.IN_PROGRESS,
      createSale: false,
      paymentMethod: PaymentMethod.CASH,
    }),
  );

  // ── Выдача с продажей ──────────────────────────────────────────────────
  console.log('\n=== Выдача заказа с продажей ===');
  const stockBefore = await stockOf(product.id);

  const issued = await orders.changeStatus(order.id, {
    status: OrderStatus.ISSUED,
    createSale: true,
    cashAccountId: account.id,
    paymentMethod: PaymentMethod.CASH,
    paidAmount: '4500000',
  });

  check('статус', issued.status, 'ISSUED');
  check('переходов больше нет', JSON.stringify(issued.availableTransitions), '[]');
  check('склад списан один раз, а не дважды', await stockOf(product.id), stockBefore - 10);
  check('деньги пришли в кассу', await balanceOf(account.id), '4500000');

  const orderSale = await prisma.sale.findFirst({ where: { orderId: order.id } });
  check('продажа привязана к заказу', orderSale !== null, true);
  check('цена взята из заказа', orderSale?.totalAmount.toString(), '4500000');

  const movements = await prisma.stockMovement.count({
    where: { productId: product.id, refId: order.id },
  });
  check('складских движений по заказу', movements, 1);

  await cleanup(companyId);

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Пройдено: ${passed}, провалено: ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

async function cleanup(companyId: string): Promise<void> {
  const products = await prisma.product.findMany({
    where: { sku: { startsWith: MARKER } },
    select: { id: true },
  });
  const productIds = products.map((p) => p.id);

  const saleIds = (
    await prisma.sale.findMany({
      where: { items: { some: { productId: { in: productIds } } } },
      select: { id: true },
    })
  ).map((s) => s.id);

  const accounts = await prisma.cashAccount.findMany({
    where: { name: { startsWith: MARKER } },
    select: { id: true },
  });

  if (saleIds.length > 0) {
    await prisma.cashTransaction.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.saleItem.deleteMany({ where: { saleId: { in: saleIds } } });
    await prisma.sale.deleteMany({ where: { id: { in: saleIds } } });
  }

  await prisma.orderItem.deleteMany({ where: { productId: { in: productIds } } });
  await prisma.order.deleteMany({ where: { customer: { name: { startsWith: MARKER } } } });
  await prisma.stockMovement.deleteMany({ where: { productId: { in: productIds } } });
  await prisma.customer.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
  await prisma.product.deleteMany({ where: { id: { in: productIds } } });

  if (accounts.length > 0) {
    await prisma.cashTransaction.deleteMany({
      where: { accountId: { in: accounts.map((a) => a.id) } },
    });
    await prisma.cashAccount.deleteMany({ where: { id: { in: accounts.map((a) => a.id) } } });
  }
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
