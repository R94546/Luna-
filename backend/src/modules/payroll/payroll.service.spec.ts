import { Prisma } from '@prisma/client';
import { EntryAmounts, derive } from './payroll.service';

const d = (v: string | number) => new Prisma.Decimal(v);

function amounts(partial: Partial<Record<keyof EntryAmounts, string | number>>): EntryAmounts {
  return {
    workAmount: d(partial.workAmount ?? 0),
    bonus: d(partial.bonus ?? 0),
    deduction: d(partial.deduction ?? 0),
    advancePaid: d(partial.advancePaid ?? 0),
  };
}

/**
 * Формула начисления — единственное место, где деньги превращаются
 * в сумму к выдаче. Ошибка здесь тихо расходится с кассой на всю ведомость,
 * поэтому она вынесена отдельной функцией и проверяется отдельно.
 */
describe('derive — суммы начисления', () => {
  it('без правок к выплате идёт вся выработка', () => {
    const { totalAccrued, toPay } = derive(amounts({ workAmount: '14880000' }));

    expect(totalAccrued.toString()).toBe('14880000');
    expect(toPay.toString()).toBe('14880000');
  });

  it('премия увеличивает начисление', () => {
    const { totalAccrued, toPay } = derive(amounts({ workAmount: '1000000', bonus: '250000' }));

    expect(totalAccrued.toString()).toBe('1250000');
    expect(toPay.toString()).toBe('1250000');
  });

  it('удержание уменьшает начисление', () => {
    const { totalAccrued } = derive(amounts({ workAmount: '1000000', deduction: '150000' }));

    expect(totalAccrued.toString()).toBe('850000');
  });

  /**
   * Аванс вычитается из выплаты, но не из начисления: начислено человеку
   * всё равно столько, сколько он заработал, — аванс лишь часть этих денег,
   * выданная раньше. Смешаешь одно с другим, и годовой отчёт по фонду
   * оплаты труда занизится на сумму всех авансов.
   */
  it('аванс уменьшает выплату, но не начисление', () => {
    const { totalAccrued, toPay } = derive(
      amounts({ workAmount: '14880000', advancePaid: '5000000' }),
    );

    expect(totalAccrued.toString()).toBe('14880000');
    expect(toPay.toString()).toBe('9880000');
  });

  it('считает всё вместе: пример из ТЗ', () => {
    const { totalAccrued, toPay } = derive(
      amounts({
        workAmount: '14880000',
        bonus: '500000',
        deduction: '200000',
        advancePaid: '5000000',
      }),
    );

    expect(totalAccrued.toString()).toBe('15180000');
    expect(toPay.toString()).toBe('10180000');
  });

  /**
   * Аванс больше начисленного — рабочий взял вперёд и не доработал.
   * Это законный минус: он переносится в следующий период как долг,
   * а не обнуляется, иначе деньги просто исчезнут из учёта.
   */
  it('допускает отрицательную выплату при переплаченном авансе', () => {
    const { toPay } = derive(amounts({ workAmount: '3000000', advancePaid: '5000000' }));

    expect(toPay.toString()).toBe('-2000000');
    expect(toPay.isNegative()).toBe(true);
  });

  it('удержание больше заработка уводит начисление в минус', () => {
    const { totalAccrued } = derive(amounts({ workAmount: '100000', deduction: '150000' }));

    expect(totalAccrued.toString()).toBe('-50000');
  });

  /**
   * Копейки обязаны сходиться точно. На float 0.1 + 0.2 !== 0.3, и по
   * ведомости из сорока человек это расходится с кассой на видимую сумму.
   */
  it('не теряет копейки на дробных суммах', () => {
    const { totalAccrued, toPay } = derive(
      amounts({ workAmount: '0.1', bonus: '0.2', advancePaid: '0.15' }),
    );

    expect(totalAccrued.toString()).toBe('0.3');
    expect(toPay.toString()).toBe('0.15');
  });

  it('держит точность на суммах в сотни миллионов', () => {
    const { totalAccrued } = derive(amounts({ workAmount: '999999999.99', bonus: '0.01' }));

    expect(totalAccrued.toString()).toBe('1000000000');
  });

  it('возвращает Decimal, а не число', () => {
    const { totalAccrued, toPay } = derive(amounts({ workAmount: '1' }));

    expect(totalAccrued).toBeInstanceOf(Prisma.Decimal);
    expect(toPay).toBeInstanceOf(Prisma.Decimal);
  });

  /** Пересчёт по уже посчитанному не должен ничего сдвигать. */
  it('идемпотентна: повторный расчёт даёт тот же результат', () => {
    const input = amounts({
      workAmount: '14880000',
      bonus: '500000',
      deduction: '200000',
      advancePaid: '5000000',
    });

    const first = derive(input);
    const second = derive(input);

    expect(second.totalAccrued.toString()).toBe(first.totalAccrued.toString());
    expect(second.toPay.toString()).toBe(first.toPay.toString());
  });
});
