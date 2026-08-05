import '../../l10n/app_localizations.dart';

/// Тексты, которые приходится сочинять клиенту.
///
/// Обычно сообщение об ошибке приходит с сервера уже переведённым — это
/// правило проекта. Но когда до сервера не дошли вовсе или он ответил
/// не тем, сказать что-то всё равно надо, а `BuildContext` в перехватчике
/// запросов недоступен.
///
/// Поэтому один держатель строк, обновляемый при смене языка, вместо
/// протаскивания локали через слой данных.
class FallbackTexts {
  const FallbackTexts._();

  static String network =
      "Server bilan aloqa yo'q. Ulanishni tekshirib, qayta urinib ko'ring";
  static String server = 'Server xatosi';
  static String Function(int code) serverWithCode = (code) =>
      'Server xatosi ($code)';

  static void applyLocale(L l10n) {
    network = l10n.errorNetwork;
    server = l10n.errorServer;
    serverWithCode = l10n.errorServerWithCode;
  }
}
