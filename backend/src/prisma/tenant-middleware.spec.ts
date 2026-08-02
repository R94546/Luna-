import { Prisma } from '@prisma/client';
import { runWithTenant } from './tenant-context';
import { createTenantMiddleware, TENANT_MODELS } from './tenant-middleware';

const COMPANY = '11111111-1111-1111-1111-111111111111';
const OTHER_COMPANY = '22222222-2222-2222-2222-222222222222';

/**
 * Прогон одного вызова через middleware.
 *
 * Возвращает params в том виде, в каком их получил бы Prisma — именно они
 * и есть предмет проверки: middleware ничего не выполняет, он переписывает
 * аргументы запроса.
 */
async function run(
  params: Partial<Prisma.MiddlewareParams>,
  companyId?: string,
): Promise<Prisma.MiddlewareParams> {
  const middleware = createTenantMiddleware();

  const full: Prisma.MiddlewareParams = {
    model: 'Product',
    action: 'findMany',
    args: undefined,
    dataPath: [],
    runInTransaction: false,
    ...params,
  };

  let seen: Prisma.MiddlewareParams | undefined;
  const next = async (p: Prisma.MiddlewareParams) => {
    seen = p;
    return null;
  };

  if (companyId) {
    await runWithTenant({ companyId }, () => middleware(full, next));
  } else {
    await middleware(full, next);
  }

  if (!seen) throw new Error('middleware не вызвал next');
  return seen;
}

describe('tenant middleware', () => {
  describe('чтение', () => {
    it('дописывает companyId в пустой where', async () => {
      const p = await run({ action: 'findMany' }, COMPANY);
      expect(p.args.where).toEqual({ companyId: COMPANY });
    });

    it('сохраняет условия вызывающего кода', async () => {
      const p = await run(
        { action: 'findMany', args: { where: { isActive: true } } },
        COMPANY,
      );
      expect(p.args.where).toEqual({ isActive: true, companyId: COMPANY });
    });

    /**
     * Главный сценарий утечки: код знает id чужой записи и запрашивает
     * её напрямую. Без дописанного companyId Prisma вернула бы данные
     * другого цеха.
     */
    it('сужает findUnique по чужому id', async () => {
      const p = await run(
        { action: 'findUnique', args: { where: { id: 'foreign-id' } } },
        COMPANY,
      );
      expect(p.args.where).toEqual({ id: 'foreign-id', companyId: COMPANY });
    });

    it.each(['count', 'aggregate', 'groupBy', 'findFirst', 'findFirstOrThrow'])(
      'фильтрует %s',
      async (action) => {
        const p = await run({ action: action as Prisma.PrismaAction }, COMPANY);
        expect(p.args.where).toMatchObject({ companyId: COMPANY });
      },
    );
  });

  describe('запись', () => {
    it('подставляет companyId в create', async () => {
      const p = await run({ action: 'create', args: { data: { name: 'Sport-12' } } }, COMPANY);
      expect(p.args.data).toEqual({ name: 'Sport-12', companyId: COMPANY });
    });

    /**
     * Инвариант, ради которого companyId дописывается ПОСЛЕ данных
     * вызывающего кода: даже прямая попытка записать в чужую компанию
     * молча превращается в запись в свою.
     */
    it('перебивает чужой companyId, переданный вызывающим кодом', async () => {
      const p = await run(
        { action: 'create', args: { data: { name: 'X', companyId: OTHER_COMPANY } } },
        COMPANY,
      );
      expect(p.args.data.companyId).toBe(COMPANY);
    });

    it('проставляет companyId каждой строке createMany', async () => {
      const p = await run(
        { action: 'createMany', args: { data: [{ name: 'A' }, { name: 'B' }] } },
        COMPANY,
      );
      expect(p.args.data).toEqual([
        { name: 'A', companyId: COMPANY },
        { name: 'B', companyId: COMPANY },
      ]);
    });

    it('обрабатывает createMany с единственным объектом вместо массива', async () => {
      const p = await run({ action: 'createMany', args: { data: { name: 'A' } } }, COMPANY);
      expect(p.args.data).toEqual({ name: 'A', companyId: COMPANY });
    });

    it('сужает update по чужому id', async () => {
      const p = await run(
        { action: 'update', args: { where: { id: 'foreign' }, data: { salePrice: '1' } } },
        COMPANY,
      );
      expect(p.args.where).toEqual({ id: 'foreign', companyId: COMPANY });
    });

    it.each(['delete', 'deleteMany', 'updateMany'])('фильтрует %s', async (action) => {
      const p = await run({ action: action as Prisma.PrismaAction }, COMPANY);
      expect(p.args.where).toMatchObject({ companyId: COMPANY });
    });

    /** upsert — единственная операция, которой нужны и where, и create. */
    it('заполняет и where, и create у upsert', async () => {
      const p = await run(
        { action: 'upsert', args: { where: { sku: 'S-1' }, create: { name: 'A' }, update: {} } },
        COMPANY,
      );
      expect(p.args.where).toEqual({ sku: 'S-1', companyId: COMPANY });
      expect(p.args.create).toEqual({ name: 'A', companyId: COMPANY });
    });
  });

  describe('что middleware не трогает', () => {
    /**
     * Без контекста запрос уходит как есть. Это осознанно: auth-слой
     * работает до входа в компанию, и требовать контекст здесь означало бы
     * невозможность войти в систему.
     */
    it('пропускает запрос без tenant-контекста', async () => {
      const p = await run({ action: 'findMany', args: { where: { isActive: true } } });
      expect(p.args.where).toEqual({ isActive: true });
    });

    const platformModels: Prisma.ModelName[] = [
      'Company',
      'User',
      'RefreshToken',
      'TelegramUpdate',
    ];

    it.each(platformModels)('не фильтрует модель платформы %s', async (model) => {
      const p = await run({ model, action: 'findMany' }, COMPANY);
      expect(p.args?.where?.companyId).toBeUndefined();
    });

    const childModels: Prisma.ModelName[] = ['OrderItem', 'SaleItem', 'CostCalculationItem'];

    it.each(childModels)(
      'не фильтрует дочернюю сущность %s — у неё нет company_id',
      async (model) => {
        const p = await run({ model, action: 'findMany' }, COMPANY);
        expect(p.args?.where?.companyId).toBeUndefined();
      },
    );

    it('пропускает неизвестное действие, не ломая запрос', async () => {
      const p = await run(
        { action: 'executeRaw' as Prisma.PrismaAction, args: { query: 'SELECT 1' } },
        COMPANY,
      );
      expect(p.args).toEqual({ query: 'SELECT 1' });
    });
  });

  /**
   * Список моделей ведётся руками, и это его слабое место: новая таблица
   * с company_id не начнёт фильтроваться сама, а забытая модель — это
   * ровно та утечка, ради которой middleware и написан.
   *
   * Поэтому сверяемся не с копией списка, а со схемой: состав полей
   * доступен в рантайме через Prisma.dmmf. Тест падает при добавлении
   * в schema.prisma сущности с company_id, не попавшей в TENANT_MODELS.
   */
  describe('состав TENANT_MODELS', () => {
    const modelsWithCompanyId = Prisma.dmmf.datamodel.models
      .filter((m) => m.fields.some((f) => f.name === 'companyId'))
      .map((m) => m.name);

    /**
     * Обе исключены сознательно:
     *   User            — привязан к компании, но читается auth-слоем
     *                     до входа в контекст, иначе не залогиниться;
     *   CompanyCounter  — правится только в nextNumber() сырым SQL,
     *                     где company_id передаётся явно.
     */
    const deliberatelyExcluded = new Set(['User', 'CompanyCounter']);

    it('покрывает все сущности схемы с company_id', () => {
      const unprotected = modelsWithCompanyId.filter(
        (name) => !TENANT_MODELS.has(name) && !deliberatelyExcluded.has(name),
      );

      expect(unprotected).toEqual([]);
    });

    it('не содержит моделей, которых нет в схеме', () => {
      const known = new Set(Prisma.dmmf.datamodel.models.map((m) => m.name));
      expect([...TENANT_MODELS].filter((name) => !known.has(name))).toEqual([]);
    });

    it('не фильтрует по company_id то, у чего его нет', () => {
      const withoutField = [...TENANT_MODELS].filter(
        (name) => !modelsWithCompanyId.includes(name),
      );
      expect(withoutField).toEqual([]);
    });
  });

  /**
   * AsyncLocalStorage должен переживать await внутри обработчика: если бы
   * контекст терялся между операциями, вторая ушла бы без фильтра.
   */
  it('сохраняет контекст между последовательными вызовами', async () => {
    const middleware = createTenantMiddleware();
    const captured: unknown[] = [];

    const call = async (action: Prisma.PrismaAction) => {
      const params: Prisma.MiddlewareParams = {
        model: 'WorkLog',
        action,
        args: {},
        dataPath: [],
        runInTransaction: false,
      };
      await middleware(params, async (p) => {
        captured.push(p.args.where);
        return null;
      });
    };

    await runWithTenant({ companyId: COMPANY }, async () => {
      await call('findMany');
      await new Promise((resolve) => setImmediate(resolve));
      await call('count');
    });

    expect(captured).toEqual([{ companyId: COMPANY }, { companyId: COMPANY }]);
  });
});
