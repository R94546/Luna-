import { PrismaClient, UserRole, WorkLogStatus, WorkLogSource } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

/**
 * Демо-данные для разработки: цех с сотрудниками, моделями, расценками
 * и выработкой за две недели. Позволяет открыть приложение и увидеть
 * заполненный дашборд, а не пустые экраны.
 *
 * Вход: +998901234567 / luna12345
 */
async function main(): Promise<void> {
  const phone = '+998901234567';

  const existing = await prisma.user.findUnique({ where: { phone } });
  if (existing) {
    console.log('Демо-данные уже созданы. Для пересоздания: npx prisma migrate reset');
    return;
  }

  const company = await prisma.company.create({
    data: {
      name: 'Luna Shoes',
      slug: 'luna-shoes',
      phone,
      // Автоподтверждение включено — как и по умолчанию для новых компаний.
      subscriptionEndsAt: new Date(Date.now() + 30 * 86_400_000),
    },
  });

  await prisma.user.create({
    data: {
      companyId: company.id,
      phone,
      fullName: 'Рустам Абдувахобов',
      passwordHash: await argon2.hash('luna12345', { type: argon2.argon2id }),
      role: UserRole.OWNER,
    },
  });

  const cashAccount = await prisma.cashAccount.create({
    data: { companyId: company.id, name: 'Asosiy kassa', isDefault: true, balance: '12400000' },
  });

  await prisma.expenseCategory.createMany({
    data: ['Ijara', "Kommunal to'lovlar", 'Materiallar', 'Transport', 'Boshqa xarajatlar'].map((name) => ({
      companyId: company.id,
      name,
      isSystem: true,
    })),
  });

  const operations = await Promise.all(
    ['Bichish', 'Tikish', 'Qolipga tortish', 'Qadoqlash'].map((name, i) =>
      prisma.operation.create({
        data: { companyId: company.id, name, sortOrder: i },
      }),
    ),
  );

  const products = await Promise.all(
    [
      { sku: 'SP-12', name: 'Krossovka «Sport-12»', salePrice: '450000', costPrice: '280000', stockQuantity: 88 },
      { sku: 'ZM-04', name: 'Botinka «Qish-4»', salePrice: '620000', costPrice: '390000', stockQuantity: 42 },
      { sku: 'KL-01', name: 'Tufli «Klassika»', salePrice: '520000', costPrice: '310000', stockQuantity: 6 },
    ].map((p) =>
      prisma.product.create({
        data: { companyId: company.id, ...p, category: 'Poyabzal', minStockLevel: 10 },
      }),
    ),
  );

  // Приход на склад — остаток обязан совпадать с журналом движений,
  // иначе триггер сверки не даст записать первое же реальное движение.
  await prisma.stockMovement.createMany({
    data: products.map((p) => ({
      companyId: company.id,
      productId: p.id,
      type: 'PRODUCTION_IN' as const,
      quantity: p.stockQuantity,
      balanceAfter: p.stockQuantity,
      note: "Boshlang'ich qoldiq",
    })),
  });

  // Базовые расценки по операциям, плюс повышенная за затяжку зимних ботинок.
  const baseRates = [8000, 18000, 12000, 5000];
  await prisma.pieceRate.createMany({
    data: operations.map((op, i) => ({
      companyId: company.id,
      operationId: op.id,
      rate: String(baseRates[i]),
    })),
  });

  await prisma.pieceRate.create({
    data: {
      companyId: company.id,
      operationId: operations[2].id,
      productId: products[1].id,
      rate: '16000',
    },
  });

  const employees = await Promise.all(
    [
      { fullName: 'Aziz Karimov', position: 'Qolipga tortuvchi', defaultOperationId: operations[2].id },
      { fullName: 'Dilshod Rahimov', position: 'Tikuvchi', defaultOperationId: operations[1].id },
      { fullName: 'Sanjar Usmonov', position: 'Bichuvchi', defaultOperationId: operations[0].id },
    ].map((e) =>
      prisma.employee.create({
        data: { companyId: company.id, ...e, hiredAt: new Date('2025-03-01') },
      }),
    ),
  );

  // Выработка за 14 дней. Все записи APPROVED: при включённом
  // автоподтверждении очередь на проверку и должна быть пустой.
  const workLogs: {
    companyId: string;
    employeeId: string;
    productId: string;
    operationId: string;
    quantity: number;
    rate: string;
    amount: string;
    workDate: Date;
    status: WorkLogStatus;
    source: WorkLogSource;
  }[] = [];

  for (let dayOffset = 14; dayOffset >= 0; dayOffset--) {
    const workDate = new Date();
    workDate.setUTCHours(0, 0, 0, 0);
    workDate.setUTCDate(workDate.getUTCDate() - dayOffset);

    if (workDate.getUTCDay() === 0) continue; // воскресенье — выходной

    employees.forEach((emp, idx) => {
      const product = products[idx % products.length];
      const operationId = emp.defaultOperationId!;
      const rate = operationId === operations[2].id && product.id === products[1].id ? 16000 : baseRates[idx === 0 ? 2 : idx === 1 ? 1 : 0];
      const quantity = 18 + ((dayOffset * 7 + idx * 5) % 12);

      workLogs.push({
        companyId: company.id,
        employeeId: emp.id,
        productId: product.id,
        operationId,
        quantity,
        rate: String(rate),
        amount: String(quantity * rate),
        workDate,
        status: WorkLogStatus.APPROVED,
        source: WorkLogSource.TELEGRAM,
      });
    });
  }

  await prisma.workLog.createMany({ data: workLogs });

  console.log(`
Демо-данные созданы.

  Компания:  ${company.name}
  Вход:      ${phone}
  Пароль:    luna12345
  Касса:     ${cashAccount.name}
  Сотрудники: ${employees.length}
  Модели:     ${products.length}
  Выработка:  ${workLogs.length} записей (все APPROVED — автоподтверждение включено)
`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
