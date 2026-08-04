import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/domain/session.dart';
import 'package:luna_app/features/auth/domain/user_role.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/catalog/presentation/catalog_screen.dart';

class _FakeAdapter implements HttpClientAdapter {
  /// Тела запросов, ушедших не на чтение, — по ним проверяем, что именно
  /// экран отправил на сервер.
  final List<Map<String, dynamic>> writes = [];
  final List<String> deleted = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'DELETE') {
      deleted.add(options.path);
      return _json({'ok': true});
    }

    if (options.method == 'POST' || options.method == 'PATCH') {
      writes.add({
        'path': options.path,
        'body': options.data as Map<String, dynamic>? ?? <String, dynamic>{},
      });

      if (options.path.endsWith('/telegram-link')) {
        return _json({
          'code': 'AB12CD',
          'deepLink': 'https://t.me/luna_bot?start=AB12CD',
          'expiresAt': '2026-08-04T12:30:00.000Z',
        });
      }

      return _json({'id': 'new-1'}, status: 201);
    }

    if (options.path == '/products') {
      return _json({
        'items': [
          {
            'id': 'p-1',
            'sku': 'SP-12',
            'name': 'Sport-12',
            'salePrice': '450000',
            'costPrice': '300000',
            'stockQuantity': 1,
            'minStockLevel': 5,
            'isLowStock': true,
          },
        ],
        'meta': {'page': 1, 'limit': 100, 'total': 1, 'totalPages': 1},
      });
    }

    if (options.path == '/employees') {
      return _json([
        {
          'id': 'e-1',
          'fullName': 'Alisher',
          'phone': '+998901112233',
          'position': 'Tikuvchi',
          'telegramLinked': false,
        },
        {
          'id': 'e-2',
          'fullName': 'Dilnoza',
          'telegramLinked': true,
        },
      ]);
    }

    if (options.path == '/operations') {
      return _json([
        {'id': 'o-1', 'name': 'Tikish', 'code': 'TK', 'sortOrder': 1},
      ]);
    }

    return _json([
      {
        'id': 'r-1',
        'operation': {'id': 'o-1', 'name': 'Tikish'},
        'product': null,
        'employee': null,
        'rate': '12000',
      },
    ]);
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

class _FakeSession extends SessionController {
  _FakeSession(this.role);

  final UserRole role;

  @override
  Future<Session?> build() async =>
      Session(userId: 'u', fullName: 'Test', phone: '+998901234567', role: role);
}

Future<_FakeAdapter> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.owner,
}) async {
  final adapter = _FakeAdapter();

  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sessionControllerProvider.overrideWith(() => _FakeSession(role)),
      ],
      child: const MaterialApp(home: CatalogScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('модели показываются с ценой и остатком', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Sport-12'), findsOneWidget);
    expect(find.textContaining('остаток 1'), findsOneWidget);
  });

  /// Остаток ниже минимального — единственное, ради чего этот список
  /// открывают срочно, поэтому он выделен цветом ошибки.
  testWidgets('заканчивающийся остаток выделен', (tester) async {
    await _pump(tester);

    final subtitle = tester.widget<Text>(find.textContaining('остаток 1'));
    final context = tester.element(find.byType(CatalogScreen));

    expect(subtitle.style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('склад двигается выбранным типом', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Склад'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '7');
    await tester.tap(find.text('Записать'));
    await tester.pumpAndSettle();

    final movement = adapter.writes.single;
    expect(movement['path'], '/stock/movements');
    expect((movement['body'] as Map)['type'], 'PURCHASE_IN');
    expect((movement['body'] as Map)['quantity'], 7);
  });

  /// Продажи и выдачи заказов склад двигают сами — руками их выбрать
  /// нельзя, иначе тот же товар списался бы дважды.
  testWidgets('продажи в типах движения нет', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Склад'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Закупка'));
    await tester.pumpAndSettle();

    expect(find.text('Брак / списание'), findsOneWidget);
    expect(find.textContaining('Продажа'), findsNothing);
  });

  testWidgets('рабочий без Telegram отличается от привязанного', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Сотрудники'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.telegram), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('код привязки запрашивается и показывается', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('Сотрудники'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подключить Telegram'));
    await tester.pumpAndSettle();

    expect(adapter.writes.single['path'], '/employees/e-1/telegram-link');
    expect(find.text('AB12CD'), findsOneWidget);
  });

  /// Пустые «модель» и «сотрудник» значат «ставка для всех» — это правило
  /// расчёта зарплаты, и список обязан его показывать словами.
  testWidgets('общая расценка подписана «для всех»', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Расценки'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Все модели'), findsOneWidget);
    expect(find.textContaining('Все сотрудники'), findsOneWidget);
  });

  /// Удаление ставки правит то, по чему считалась зарплата.
  testWidgets('мастер расценку удалить не может', (tester) async {
    await _pump(tester, role: UserRole.admin);

    await tester.tap(find.text('Расценки'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('владелец расценку удаляет', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('Расценки'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Да'));
    await tester.pumpAndSettle();

    expect(adapter.deleted, ['/piece-rates/r-1']);
  });
}
