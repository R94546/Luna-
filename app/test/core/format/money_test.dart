import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/format/money.dart';

/// Неразрывный пробел.
///
/// Money ставит именно его: обычный пробел позволил бы перенести строку
/// посреди суммы, и число разъехалось бы по двум строкам карточки.
/// В тесте он записан escape-последовательностью — иначе отличить его
/// от обычного пробела при чтении невозможно.
const nbsp = '\u00A0';

void main() {
  group('Money.parse', () {
    test('разбирает строку с копейками без потери точности', () {
      expect(Money.parse('84300000.00'), Decimal.parse('84300000.00'));
      expect(Money.parse('0.1'), Decimal.parse('0.1'));
    });

    /// Ради этого суммы и передаются строками: 0.1 + 0.2 в double не даёт 0.3,
    /// и на ведомости из сорока человек это расходится с кассой.
    test('складывает копейки точно, в отличие от double', () {
      final sum = Money.parse('0.1') + Money.parse('0.2');

      expect(sum, Decimal.parse('0.3'));
      expect(sum.toString(), '0.3');
    });

    test('null и мусор превращаются в ноль, а не в исключение', () {
      expect(Money.parse(null), Decimal.zero);
      expect(Money.parse('не число'), Decimal.zero);
      expect(Money.parse(''), Decimal.zero);
    });

    test('принимает число', () {
      expect(Money.parse(1500), Decimal.fromInt(1500));
    });
  });

  group('Money.format', () {
    test('разделяет разряды', () {
      expect(
        Money.format('84300000', withCurrency: false),
        '84${nbsp}300${nbsp}000',
      );
      expect(Money.format('1000', withCurrency: false), '1${nbsp}000');
      expect(Money.format('999', withCurrency: false), '999');
    });

    test('добавляет валюту', () {
      expect(Money.format('12400000'), '12${nbsp}400${nbsp}000$nbspсум');
    });

    test('ноль остаётся нулём', () {
      expect(Money.format('0', withCurrency: false), '0');
    });

    test('отрицательная сумма сохраняет знак', () {
      expect(
        Money.format('-2000000', withCurrency: false),
        '-2${nbsp}000${nbsp}000',
      );
    });

    /// В цехе считают в сумах, копеек в обороте нет — «,00» съедало бы
    /// ширину карточки, где рядом ещё четыре суммы.
    test('копейки отбрасываются округлением', () {
      expect(Money.format('1500.49', withCurrency: false), '1${nbsp}500');
      expect(Money.format('1500.50', withCurrency: false), '1${nbsp}501');
    });
  });

  group('Money.compact', () {
    test('миллионы', () {
      expect(Money.compact('84300000'), '84,3$nbspмлн');
      expect(Money.compact('1000000'), '1,0$nbspмлн');
    });

    test('миллиарды', () {
      expect(Money.compact('2500000000'), '2,5$nbspмлрд');
    });

    test('тысячи', () {
      expect(Money.compact('12500'), '12,5$nbspтыс');
    });

    test('мелкие суммы показываются целиком', () {
      expect(Money.compact('999'), '999');
      expect(Money.compact('0'), '0');
    });

    /// «842,7 млн» читается хуже, чем «843 млн», а точность здесь мнимая.
    test('от ста дробная часть не показывается', () {
      expect(Money.compact('842700000'), '843$nbspмлн');
    });

    test('отрицательные суммы сохраняют знак', () {
      expect(Money.compact('-5000000'), '-5,0$nbspмлн');
    });
  });

  group('Money.change', () {
    test('рост со знаком плюс', () {
      expect(Money.change(12.4), '+12.4%');
      expect(Money.change(20), '+20%');
    });

    test('падение со знаком минус', () {
      expect(Money.change(-3.2), '-3.2%');
    });

    test('ноль без знака', () {
      expect(Money.change(0), '0%');
    });

    /// Рост с нуля процентами не выражается: бэкенд честно отдаёт null,
    /// и показать «0%» значило бы соврать, что ничего не изменилось.
    test('null — прочерк, а не ноль процентов', () {
      expect(Money.change(null), '—');
    });
  });
}
