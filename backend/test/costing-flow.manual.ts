/**
 * Себестоимость на живой БД.
 *
 * Проверяется не «эндпоинт отвечает», а что цифры сходятся: материалы
 * берутся по цене справочника, работа — по действующим расценкам, а
 * применённый расчёт доезжает до карточки модели. Ошибка здесь тихо
 * искажает прибыль в каждом отчёте: продажа считает выгоду от `costPrice`.
 *
 * Скрипт заводит свои данные и убирает их за собой.
 *
 * Запуск:
 *   npm run test:costing
 */
import { CostingService } from '../src/modules/costing/costing.service';
import { MaterialsService } from '../src/modules/materials/materials.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { runWithTenant } from '../src/prisma/tenant-context';

const prisma = new PrismaService();
const materials = new MaterialsService(prisma);
const costing = new CostingService(prisma);

const MARKER = 'COSTING-TEST';

let passed = 0;
let failed = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = String(actual) === String(expected);
  if (ok) passed++;
  else failed++;
  console.log(`  ${ok ? '✅' : '❌'} ${label}: ${actual}${ok ? '' : ` (ожидалось ${expected})`}`);
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
      salePrice: '500000',
      costPrice: '111111',
    },
  });

  const leather = await materials.create({
    name: `${MARKER} kozha`,
    unit: 'дм²',
    unitPrice: '34000',
  });

  // Операции с расценками: работа должна прийти отсюда, а не из воздуха.
  const stitching = await prisma.operation.create({
    data: { companyId, name: `${MARKER} poshiv`, sortOrder: 990 },
  });
  const packing = await prisma.operation.create({
    data: { companyId, name: `${MARKER} upakovka`, sortOrder: 991 },
  });

  await prisma.pieceRate.create({
    data: { companyId, operationId: stitching.id, productId: product.id, rate: '18000' },
  });
  await prisma.pieceRate.create({
    data: { companyId, operationId: packing.id, productId: product.id, rate: '15000' },
  });

  console.log('\n=== Расчёт без сохранения ===');

  const result = await costing.calculate({
    productId: product.id,
    items: [
      { materialId: leather.id, quantity: 2.5 },
      // Разовый материал: цена своя, в справочник не попадает.
      { name: 'Podoshva', unit: 'пара', unitPrice: '35000', quantity: 1 },
    ],
    overheadCost: '15000',
    timeMinutes: 45,
    marginPercent: 30,
  });

  check('материалы', result.materialsCost.toString(), '120000');
  // Работа не передавалась — сложена из расценок: 18000 + 15000.
  check('работа из расценок', result.laborCost.toString(), '33000');
  check('операций в разбивке', result.laborBreakdown.length, 2);
  check('накладные', result.overheadCost.toString(), '15000');
  check('себестоимость', result.totalCost.toString(), '168000');
  // Наценка на себестоимость: 168000 × 1.3.
  check('рекомендованная цена', result.recommendedPrice.toString(), '218400');
  check('прибыль с пары', result.profitPerUnit.toString(), '50400');

  console.log('\n=== Цена берётся из справочника ===');

  // Кожа подорожала — расчёт обязан это увидеть без правки запроса.
  await materials.update(leather.id, { unitPrice: '40000' });

  const afterRise = await costing.calculate({
    productId: product.id,
    items: [{ materialId: leather.id, quantity: 2.5 }],
    overheadCost: '0',
    timeMinutes: 0,
    marginPercent: 30,
  });

  check('материалы по новой цене', afterRise.materialsCost.toString(), '100000');

  // Цену из запроса подсунуть нельзя: справочник главнее.
  const spoofed = await costing.calculate({
    productId: product.id,
    items: [{ materialId: leather.id, quantity: 1, unitPrice: '1' }],
    overheadCost: '0',
    timeMinutes: 0,
    marginPercent: 0,
  });
  check('подменить цену справочника нельзя', spoofed.materialsCost.toString(), '40000');

  console.log('\n=== Расценки со сроком ===');

  // Прошлогодняя расценка не должна занижать себестоимость.
  await prisma.pieceRate.updateMany({
    where: { operationId: packing.id, productId: product.id },
    data: { validTo: new Date('2020-01-01') },
  });

  const afterExpiry = await costing.calculate({
    productId: product.id,
    items: [{ materialId: leather.id, quantity: 1 }],
    overheadCost: '0',
    timeMinutes: 0,
    marginPercent: 0,
  });
  check('истёкшая расценка выпала', afterExpiry.laborCost.toString(), '18000');

  console.log('\n=== Сохранение и применение ===');

  const saved = await costing.create({
    name: `${MARKER} raschet`,
    productId: product.id,
    items: [
      { materialId: leather.id, quantity: 2 },
      { name: 'Podoshva', unit: 'пара', unitPrice: '35000', quantity: 1 },
    ],
    overheadCost: '10000',
    timeMinutes: 40,
    marginPercent: 25,
  });

  check('позиций сохранено', saved.items.length, 2);
  check('себестоимость записана', saved.totalCost.toString(), '143000');
  check('пока не применён', saved.isApplied, false);

  const before = await prisma.product.findFirstOrThrow({ where: { id: product.id } });
  check('цена модели не тронута', before.costPrice.toString(), '111111');

  const applied = await costing.apply(saved.id);
  check('расчёт помечен применённым', applied.isApplied, true);

  const after = await prisma.product.findFirstOrThrow({ where: { id: product.id } });
  check('себестоимость доехала до модели', after.costPrice.toString(), '143000');

  // Второй применённый расчёт снимает флаг с первого: «текущая цифра»
  // в карточке может быть только одна.
  const second = await costing.create({
    name: `${MARKER} raschet 2`,
    productId: product.id,
    items: [{ materialId: leather.id, quantity: 1 }],
    overheadCost: '0',
    timeMinutes: 0,
    marginPercent: 0,
  });
  await costing.apply(second.id);

  const first = await prisma.costCalculation.findFirstOrThrow({ where: { id: saved.id } });
  check('прежний расчёт больше не текущий', first.isApplied, false);

  console.log('\n=== Снимок цен ===');

  // Материал удалили — сохранённый расчёт обязан остаться читаемым.
  await materials.remove(leather.id);
  const stored = await costing.findOne(saved.id);
  const item = stored.items.find((row) => row.name.includes('kozha'));

  check('название сохранилось', item?.name, `${MARKER} kozha`);
  check('цена на момент расчёта', item?.unitPrice.toString(), '40000');

  console.log('\n=== Отказы ===');

  const orphan = await costing.create({
    name: `${MARKER} bez modeli`,
    items: [{ name: 'Klej', unit: 'кг', unitPrice: '20000', quantity: 1 }],
    overheadCost: '0',
    timeMinutes: 0,
    marginPercent: 10,
  });

  // Без модели применять некуда — это ошибка, а не молчаливый пропуск.
  let rejected = 'применил';
  try {
    await costing.apply(orphan.id);
  } catch {
    rejected = 'отказал';
  }
  check('расчёт без модели', rejected, 'отказал');

  // Работа без модели — ноль, а не падение: считают и «на глазок».
  check('работа без модели', orphan.laborCost.toString(), '0');

  await cleanup(companyId);

  console.log(`\nИтог: ${passed} успешно, ${failed} провалено`);
  if (failed > 0) process.exitCode = 1;
}

async function cleanup(companyId: string): Promise<void> {
  const calculations = await prisma.costCalculation.findMany({
    where: { companyId, name: { startsWith: MARKER } },
    select: { id: true },
  });
  const ids = calculations.map((c) => c.id);

  if (ids.length > 0) {
    await prisma.costCalculationItem.deleteMany({ where: { calculationId: { in: ids } } });
    await prisma.costCalculation.deleteMany({ where: { id: { in: ids } } });
  }

  await prisma.pieceRate.deleteMany({ where: { operation: { name: { startsWith: MARKER } } } });
  await prisma.operation.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
  await prisma.material.deleteMany({ where: { companyId, name: { startsWith: MARKER } } });
  await prisma.product.deleteMany({ where: { companyId, sku: { startsWith: MARKER } } });
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
