import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_controller.g.dart';

/// Языки приложения. Узбекский первый — на нём работает цех.
const supportedLocales = [Locale('uz'), Locale('ru')];

/// Выбранный язык.
///
/// `null` — «как в системе»: телефон мастера настроен на узбекский, и
/// спрашивать язык при каждой установке незачем. Явный выбор нужен там,
/// где система стоит на языке, которого в приложении нет: без него
/// человек получил бы узбекский по умолчанию и не понял, где это менять.
///
/// Хранится рядом с токенами — отдельное хранилище ради одной строки
/// заводить не стоит. На web его нет, и выбор живёт до перезагрузки:
/// web у нас инструмент разработки.
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  static const _key = 'luna.locale';

  @override
  Locale? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    if (kIsWeb) return;

    final saved = await const FlutterSecureStorage().read(key: _key);
    if (saved == null) return;

    state = Locale(saved);
  }

  Future<void> select(Locale? locale) async {
    state = locale;

    if (kIsWeb) return;

    const storage = FlutterSecureStorage();

    if (locale == null) {
      await storage.delete(key: _key);
      return;
    }

    await storage.write(key: _key, value: locale.languageCode);
  }
}

/// Язык, на котором приложение показывается сейчас.
///
/// Нужен не для отрисовки, а для заголовка `Accept-Language`: тексты
/// ошибок приходят с сервера, и приходить они должны на том языке, на
/// котором человек читает экран, а не на языке прошивки телефона.
Locale resolveLocale(Locale? selected) {
  if (selected != null) return selected;

  final system = PlatformDispatcher.instance.locale;

  return supportedLocales.any((l) => l.languageCode == system.languageCode)
      ? Locale(system.languageCode)
      : supportedLocales.first;
}
