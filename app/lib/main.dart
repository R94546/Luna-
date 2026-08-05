import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/format/money.dart';
import 'core/l10n/fallback_texts.dart';
import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const ProviderScope(child: LunaApp()));
}

class LunaApp extends ConsumerWidget {
  const LunaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Luna',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      // Узбекский — основной язык цеха, русский запасной. Тексты ошибок
      // приходят с сервера по Accept-Language и опираются на этот же
      // выбор: язык экрана и язык ошибки обязаны совпадать.
      locale: ref.watch(localeControllerProvider),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Суммы форматируются без BuildContext — из карточек, диалогов и
        // провайдеров. Протаскивать локаль в полсотни мест ради слова
        // «сум» дороже, чем обновить его здесь при смене языка.
        Money.applyLocale(L.of(context));
        FallbackTexts.applyLocale(L.of(context));
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
