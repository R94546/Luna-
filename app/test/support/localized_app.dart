import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:luna_app/core/format/money.dart';
import 'package:luna_app/core/l10n/fallback_texts.dart';
import 'package:luna_app/core/l10n/locale_controller.dart';
import 'package:luna_app/l10n/app_localizations.dart';

/// Оболочка экрана для тестов — то же, что делает `LunaApp`.
///
/// Язык по умолчанию русский, а не узбекский: тесты проверяют поведение,
/// а не перевод, и держать в них две сотни узбекских строк значит платить
/// за каждую правку формулировки дважды. Узбекский проверяется отдельно —
/// тем, что экран на нём вообще собирается и показывает свои подписи.
Widget localizedApp(Widget child, {Locale locale = const Locale('ru')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: supportedLocales,
    localizationsDelegates: const [
      L.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
    builder: (context, widget) {
      // Суммы и запасные тексты ошибок берут подписи отсюда — в приложении
      // это делает тот же builder.
      Money.applyLocale(L.of(context));
      FallbackTexts.applyLocale(L.of(context));
      return widget ?? const SizedBox.shrink();
    },
  );
}
