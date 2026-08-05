import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/api/dio_client.dart';
import 'package:luna_app/core/l10n/locale_controller.dart';
import 'package:luna_app/core/storage/token_store.dart';
import 'package:luna_app/features/settings/presentation/settings_screen.dart';

import '../../support/localized_app.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<String?> languages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    languages.add(options.headers['Accept-Language'] as String?);

    if (options.path == '/notifications') {
      return _json({'items': <Object>[], 'unread': 0});
    }

    return _json({'ok': true});
  }

  static ResponseBody _json(Object data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// Экран настроек, язык которого задаёт сам контроллер, — как в приложении.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return localizedApp(
      const SettingsScreen(),
      locale: ref.watch(localeControllerProvider) ?? const Locale('uz'),
    );
  }
}

void main() {
  testWidgets('язык переключается и экран перерисовывается', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _App()));
    await tester.pumpAndSettle();

    // По умолчанию — узбекский: это язык цеха.
    expect(find.text('Sozlamalar'), findsOneWidget);
    expect(find.text('Настройки'), findsNothing);

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Sozlamalar'), findsNothing);
  });

  /// Язык читается на каждом запросе, а не запоминается при сборке клиента:
  /// иначе после переключения экран узбекский, а ошибки из-под него ещё
  /// какое-то время приходят по-русски.
  test('Accept-Language идёт следом за выбором', () async {
    final adapter = _FakeAdapter();
    var locale = const Locale('uz');

    final client = DioClient(
      store: InMemoryTokenStore(),
      onSessionExpired: () async {},
      locale: () => locale,
      baseUrl: 'http://test',
    )..dio.httpClientAdapter = adapter;

    await client.dio.get<Map<String, dynamic>>('/ping');
    expect(adapter.languages.last, 'uz');

    locale = const Locale('ru');

    await client.dio.get<Map<String, dynamic>>('/ping');
    expect(adapter.languages.last, 'ru');
  });
}
