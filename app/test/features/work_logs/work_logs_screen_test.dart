import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/domain/session.dart';
import 'package:luna_app/features/auth/domain/user_role.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/work_logs/presentation/work_logs_screen.dart';

/// Сервер, отдающий заготовленный список и считающий вызовы.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.total = 2});

  final int total;

  /// Маленькая страница: две записи уже дают вторую страницу.
  static const pageSize = 2;

  int listCalls = 0;
  final List<String> approved = [];
  List<String> bulkIds = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/approve')) {
      approved.add(options.path.split('/')[2]);
      return _json({'ok': true});
    }

    if (options.path.endsWith('/bulk-approve')) {
      final body = options.data as Map<String, dynamic>;
      bulkIds = List<String>.from(body['ids'] as List);
      return _json({'approved': bulkIds.length, 'skipped': 0});
    }

    listCalls++;
    final page = int.tryParse('${options.queryParameters['page']}') ?? 1;
    final from = (page - 1) * pageSize;
    final count = (total - from).clamp(0, pageSize);

    return _json({
      'items': [for (var i = 0; i < count; i++) _item(from + i)],
      'meta': {
        'page': page,
        'limit': pageSize,
        'total': total,
        'totalPages': (total / pageSize).ceil().clamp(1, 999),
      },
      'summary': {'totalQuantity': 168, 'totalAmount': '2016000.00'},
    });
  }

  Map<String, dynamic> _item(int index) => {
    'id': 'log-$index',
    'employee': {'id': 'e-$index', 'fullName': 'Xodim $index'},
    'product': {'id': 'p', 'name': 'Sport-12', 'sku': 'SP'},
    'operation': {'id': 'o', 'name': 'Tikish'},
    'quantity': 24,
    'rate': '12000.00',
    'amount': '288000.00',
    'workDate': '2026-08-01T00:00:00.000Z',
    'status': 'PENDING',
    'source': 'TELEGRAM',
  };

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

class _FakeSession extends SessionController {
  _FakeSession(this.role);

  final UserRole role;

  @override
  Future<Session?> build() async => Session(
    userId: 'u',
    fullName: 'Test',
    phone: '+998901234567',
    role: role,
  );
}

Future<_FakeAdapter> _pumpScreen(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
  int total = 2,
}) async {
  final adapter = _FakeAdapter(total: total);

  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sessionControllerProvider.overrideWith(() => _FakeSession(role)),
      ],
      child: const MaterialApp(home: WorkLogsScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('показывает записи и итоги по всей выборке', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Xodim 0'), findsOneWidget);
    expect(find.text('Xodim 1'), findsOneWidget);
    // Итоги приходят с сервера по фильтру, а не считаются по видимым строкам.
    expect(find.text('168 пар'), findsOneWidget);
  });

  testWidgets('пустой список объясняет, откуда берутся данные', (tester) async {
    await _pumpScreen(tester, total: 0);

    expect(find.text('Записей нет'), findsOneWidget);
    expect(find.textContaining('Telegram'), findsOneWidget);
  });

  testWidgets('мастер видит кнопки подтверждения', (tester) async {
    await _pumpScreen(tester, role: UserRole.admin);

    expect(find.text('Принять'), findsNWidgets(2));
    expect(find.text('Отклонить'), findsNWidgets(2));
  });

  /// Бухгалтеру эти эндпоинты закрыты на бэкенде: показать ему кнопку
  /// значит обещать действие, которое вернёт 403.
  testWidgets('бухгалтер кнопок подтверждения не видит', (tester) async {
    await _pumpScreen(tester, role: UserRole.accountant);

    expect(find.text('Xodim 0'), findsOneWidget);
    expect(find.text('Принять'), findsNothing);
    expect(find.text('Отклонить'), findsNothing);
  });

  testWidgets('нажатие «Принять» отправляет запрос по этой записи', (
    tester,
  ) async {
    final adapter = await _pumpScreen(tester);

    await tester.tap(find.text('Принять').first);
    await tester.pumpAndSettle();

    expect(adapter.approved, ['log-0']);
  });

  /// Утром мастер закрывает вчерашние отчёты одним нажатием — по одному
  /// это двадцать тапов, и половину он не сделает.
  testWidgets('длинное нажатие включает выбор пачкой', (tester) async {
    await _pumpScreen(tester);

    await tester.longPress(find.text('Xodim 0'));
    await tester.pumpAndSettle();

    expect(find.text('Выбрано: 1'), findsOneWidget);
    // В режиме выбора поштучных кнопок нет: два способа сделать одно
    // и то же на одном экране только путают.
    expect(find.text('Принять'), findsNothing);
    expect(find.text('Принять всё'), findsOneWidget);
  });

  testWidgets('пачкой уходят все выбранные записи', (tester) async {
    final adapter = await _pumpScreen(tester);

    await tester.longPress(find.text('Xodim 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xodim 1'));
    await tester.pumpAndSettle();

    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tester.tap(find.text('Принять всё'));
    await tester.pumpAndSettle();

    expect(adapter.bulkIds, ['log-0', 'log-1']);
    expect(find.text('Принято записей: 2'), findsOneWidget);
  });

  testWidgets('повторное нажатие снимает выбор', (tester) async {
    await _pumpScreen(tester);

    await tester.longPress(find.text('Xodim 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xodim 0'));
    await tester.pumpAndSettle();

    // Выбор опустел — режим выбора закончился сам.
    expect(find.text('Выбрано: 1'), findsNothing);
    expect(find.text('Принять'), findsNWidgets(2));
  });

  testWidgets('смена фильтра перезапрашивает список', (tester) async {
    final adapter = await _pumpScreen(tester);
    final before = adapter.listCalls;

    await tester.tap(find.text('Принято'));
    await tester.pumpAndSettle();

    expect(adapter.listCalls, greaterThan(before));
  });
}
