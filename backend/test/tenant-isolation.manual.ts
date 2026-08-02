/**
 * Ручная проверка изоляции арендаторов — самого критичного механизма системы.
 *
 * Проверяет, что пользователь компании B не может ни прочитать, ни изменить
 * данные компании A даже зная точный ID записи, и что create без явного
 * companyId получает его из контекста.
 *
 * Запуск (нужна поднятая БД с демо-данными):
 *   DATABASE_URL=... npx ts-node test/tenant-isolation.manual.ts
 *
 * Не .spec.ts намеренно: это интеграционная проверка против живой БД,
 * в юнит-прогон `npm test` она попадать не должна.
 */
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

async function main() {
  const prisma = new PrismaService();

  const [a, b] = await Promise.all([
    prisma.company.findFirst({ where: { slug: 'luna-shoes' } }),
    prisma.company.upsert({
      where: { slug: 'other-workshop' },
      create: { name: 'Чужой цех', slug: 'other-workshop' },
      update: {},
    }),
  ]);

  if (!a) {
    throw new Error('Компания luna-shoes не найдена — сначала выполните `npm run seed`.');
  }

  console.log(`Компания A: ${a.name}\nКомпания B: ${b.name}\n`);

  await runWithTenant({ companyId: a.id }, async () => {
    const products = await prisma.product.findMany();
    const logs = await prisma.workLog.count();
    console.log(`[контекст A] products: ${products.length}, work_logs: ${logs}`);
  });

  await runWithTenant({ companyId: b.id }, async () => {
    const products = await prisma.product.findMany();
    const logs = await prisma.workLog.count();
    console.log(`[контекст B] products: ${products.length}, work_logs: ${logs}   ← должно быть 0/0`);
  });

  // Самое опасное: знаем ID чужой записи и запрашиваем напрямую по нему.
  const victim = await prisma.product.findFirst({ where: { companyId: a.id } });

  if (!victim) {
    throw new Error('У компании A нет товаров — проверять нечего, выполните `npm run seed`.');
  }

  await runWithTenant({ companyId: b.id }, async () => {
    const stolen = await prisma.product.findUnique({ where: { id: victim.id } });
    console.log(`[контекст B] findUnique по чужому id → ${stolen === null ? 'null ✅' : 'ДАННЫЕ УТЕКЛИ ❌'}`);

    const updated = await prisma.product.updateMany({
      where: { id: victim.id },
      data: { salePrice: '1' },
    });
    console.log(`[контекст B] попытка изменить чужую запись → изменено строк: ${updated.count} ${updated.count === 0 ? '✅' : '❌'}`);
  });

  // create без явного companyId должен получить его из контекста
  await runWithTenant({ companyId: b.id }, async () => {
    const created = await prisma.product.create({
      data: { sku: 'TEST-1', name: 'Тест', salePrice: '100', costPrice: '50' } as never,
    });
    console.log(`[контекст B] create без companyId → проставлен ${created.companyId === b.id ? 'верно ✅' : 'НЕВЕРНО ❌'}`);
    await prisma.product.deleteMany({ where: { sku: 'TEST-1' } });
  });

  await prisma.company.delete({ where: { id: b.id } });
  await prisma.$disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });
