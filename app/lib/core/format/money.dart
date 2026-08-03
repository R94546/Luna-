import 'package:decimal/decimal.dart';

/// Работа с суммами.
///
/// Бэкенд отдаёт деньги строками (`"84300000.00"`) именно потому, что
/// `double` теряет копейки: 0.1 + 0.2 там не равно 0.3, и на ведомости
/// из сорока человек это расходится с кассой на видимую сумму. Разбирать
/// такие строки в `double` — значит вернуть проблему, от которой уходили.
class Money {
  const Money._();

  /// Разбор суммы из ответа API. Мусор превращается в ноль, а не в исключение:
  /// уронить весь дашборд из-за одного кривого поля хуже, чем показать ноль.
  static Decimal parse(Object? value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;

    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }

  /// «84 300 000 сум».
  ///
  /// Неразрывный пробел между разрядами и перед единицей: сумма не должна
  /// разрываться переносом строки посреди числа.
  static String format(Object? value, {bool withCurrency = true}) {
    final amount = parse(value);
    final formatted = _group(amount);

    return withCurrency ? '$formatted сум' : formatted;
  }

  /// Компактный вид для карточек: «84,3 млн».
  ///
  /// На дашборде рядом пять сумм, и полные девять цифр в каждой не помещаются
  /// в ширину телефона — их пришлось бы уменьшать до нечитаемого размера.
  static String compact(Object? value) {
    final amount = parse(value);
    final abs = amount.abs();
    final sign = amount.sign < 0 ? '-' : '';

    if (abs >= Decimal.fromInt(1000000000)) {
      return '$sign${_short(abs, 1000000000)} млрд';
    }
    if (abs >= Decimal.fromInt(1000000)) {
      return '$sign${_short(abs, 1000000)} млн';
    }
    if (abs >= Decimal.fromInt(1000)) {
      return '$sign${_short(abs, 1000)} тыс';
    }

    return _group(amount);
  }

  /// Проценты динамики. `null` — не «0%», а прочерк.
  ///
  /// Рост с нуля процентами не выражается, и бэкенд честно отдаёт null
  /// вместо выдуманной цифры. Показать «0%» значило бы соврать, что
  /// ничего не изменилось.
  static String change(num? percent) {
    if (percent == null) return '—';

    final sign = percent > 0 ? '+' : '';
    final value = percent == percent.roundToDouble()
        ? percent.round().toString()
        : percent.toStringAsFixed(1);

    return '$sign$value%';
  }

  static String _short(Decimal abs, int divisor) {
    final value = (abs / Decimal.fromInt(divisor)).toDouble();

    // Одна цифра после запятой до 100, дальше она уже не несёт смысла:
    // «842,7 млн» читается хуже, чем «843 млн».
    return value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Разряды по три цифры. Дробная часть отбрасывается: в цехе считают
  /// в сумах, копеек в обороте нет, а лишние ",00" съедают ширину.
  static String _group(Decimal value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    return rounded.sign < 0 ? '-$buffer' : buffer.toString();
  }
}
