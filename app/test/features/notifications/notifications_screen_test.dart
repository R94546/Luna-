import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/notifications/presentation/notifications_screen.dart';

class _FakeAdapter implements HttpClientAdapter {
  /// Сколько уведомлений не прочитано. Меняется вызовами, как на сервере.
  int unread = 2;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');

    if (options.path == '/notifications/read-all') {
      unread = 0;
      return _json({'updated': 2});
    }

    if (options.path.endsWith('/read')) {
      unread = unread > 0 ? unread - 1 : 0;
      return _json({'ok': true});
    }

    return _json({
      'items': [
        {
          'id': 'n-1',
          'type': 'LOW_STOCK',
          'title': 'Товар заканчивается',
          'body': 'Botinka «Qish-4» (3)',
          'isRead': unread == 0,
          'createdAt': DateTime.now().toIso8601String(),
        },
        {
          'id': 'n-2',
          'type': 'ORDER_OVERDUE',
          'title': 'Заказы просрочены',
          'body': '№14 — срок вышел',
          'isRead': unread == 0,
          'createdAt': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
      ],
      'unread': unread,
    });
  }

  static ResponseBody _json(Object data, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(data),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Future<_FakeAdapter> _pump(WidgetTester tester) async {
  final adapter = _FakeAdapter();

  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: NotificationsScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('показывает ленту', (tester) async {
    await _pump(tester);

    expect(find.text('Товар заканчивается'), findsOneWidget);
    expect(find.text('Заказы просрочены'), findsOneWidget);
  });

  testWidgets('«Прочитать все» видно, только пока есть непрочитанные', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Прочитать все'), findsOneWidget);

    await tester.tap(find.text('Прочитать все'));
    await tester.pumpAndSettle();

    expect(find.text('Прочитать все'), findsNothing);
  });

  testWidgets('нажатие на уведомление отмечает его прочитанным', (
    tester,
  ) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('Товар заканчивается'));
    await tester.pumpAndSettle();

    expect(adapter.calls, contains('POST /notifications/n-1/read'));
  });
}
