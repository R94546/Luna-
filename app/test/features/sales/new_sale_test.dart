import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/sales/presentation/widgets/new_sale_sheet.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<String?> saleKeys = [];
  final List<Map<String, dynamic>> saleBodies = [];

  /// Сколько первых попыток уронить.
  int failFirst = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/cash/accounts') {
      return _json([
        {
          'id': 'acc-1',
          'name': 'Asosiy kassa',
          'type': 'CASH',
          'balance': '12400000',
          'isDefault': true,
        },
      ]);
    }

    if (options.path == '/products') {
      return _json({
        'items': [
          {
            'id': 'p-1',
            'sku': 'SP-12',
            'name': 'Sport-12',
            'salePrice': '450000',
            'stockQuantity': 2,
          },
          {
            'id': 'p-2',
            'sku': 'QS-4',
            'name': 'Qish-4',
            'salePrice': '620000',
            'stockQuantity': 0,
          },
        ],
        'meta': {'page': 1, 'limit': 100, 'total': 2, 'totalPages': 1},
      });
    }

    saleKeys.add(options.headers['Idempotency-Key'] as String?);
    saleBodies.add(options.data as Map<String, dynamic>);

    if (saleKeys.length <= failFirst) {
      return _json({
        'code': 'NETWORK',
        'message': 'Нет связи с сервером',
      }, status: 500);
    }

    return _json({
      'id': 'sale-1',
      'saleNumber': 203,
      'paymentMethod': 'CASH',
      'soldAt': '2026-08-20T12:00:00.000Z',
      'totalAmount': '900000',
      'items': <dynamic>[],
    }, status: 201);
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

Future<_FakeAdapter> _pump(WidgetTester tester, {int failFirst = 0}) async {
  final adapter = _FakeAdapter()..failFirst = failFirst;

  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: Scaffold(body: NewSaleSheet())),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

/// Кнопка «плюс» в строке конкретного товара.
///
/// Ищем именно IconButton, а не иконку внутри него: доступность проверяется
/// по `onPressed`, а у Icon такого свойства нет.
Finder _plusFor(String product) => find.ancestor(
  of: find.descendant(
    of: find.ancestor(of: find.text(product), matching: find.byType(Card)),
    matching: find.byIcon(Icons.add_circle_outline),
  ),
  matching: find.byType(IconButton),
);

void main() {
  testWidgets('показывает товары с остатком и ценой', (tester) async {
    await _pump(tester);

    expect(find.text('Sport-12'), findsOneWidget);
    expect(find.textContaining('остаток 2'), findsOneWidget);
  });

  testWidgets('без позиций кнопка продажи недоступна', (tester) async {
    await _pump(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Продать'),
    );

    expect(button.onPressed, isNull);
  });

  /// Больше остатка набрать нельзя: сервер откажет с INSUFFICIENT_STOCK,
  /// и давать набрать заведомо неверное количество незачем.
  testWidgets('нельзя набрать больше остатка', (tester) async {
    await _pump(tester);

    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();
    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();

    // Остаток 2 — плюс должен погаснуть.
    final plus = tester.widget<IconButton>(_plusFor('Sport-12'));
    expect(plus.onPressed, isNull);
  });

  testWidgets('товар без остатка добавить нельзя', (tester) async {
    await _pump(tester);

    final plus = tester.widget<IconButton>(_plusFor('Qish-4'));
    expect(plus.onPressed, isNull);
  });

  testWidgets('итог считается по выбранным позициям', (tester) async {
    await _pump(tester);

    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();

    // 450 000 × 1
    expect(find.textContaining('450'), findsWidgets);
  });

  testWidgets('продажа уходит с ключом и позициями', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продать'));
    await tester.pumpAndSettle();

    expect(adapter.saleKeys, hasLength(1));
    expect(adapter.saleKeys.first, matches(RegExp(r'^[0-9a-f-]{36}$')));

    final body = adapter.saleBodies.first;
    expect(body['paymentMethod'], 'CASH');
    expect(body['cashAccountId'], 'acc-1');
    expect(body['items'], [
      {'productId': 'p-1', 'quantity': 1, 'unitPrice': '450000'},
    ]);
  });

  /// Связь оборвалась, человек жмёт «Продать» ещё раз. Повтор обязан уйти
  /// с тем же ключом: иначе товар спишется со склада дважды.
  testWidgets('повтор после ошибки идёт с тем же ключом', (tester) async {
    final adapter = await _pump(tester, failFirst: 1);

    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Продать'));
    await tester.pumpAndSettle();
    expect(find.textContaining('связи'), findsOneWidget);

    await tester.tap(find.text('Продать'));
    await tester.pumpAndSettle();

    expect(adapter.saleKeys, hasLength(2));
    expect(adapter.saleKeys.first, adapter.saleKeys.last);
  });

  /// В долг деньги в кассу не приходят — кассу выбирать не нужно,
  /// и в запрос она не попадает.
  testWidgets('в долг касса не передаётся', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(_plusFor('Sport-12'));
    await tester.pumpAndSettle();

    // Открываем список способов оплаты по его текущему значению.
    await tester.tap(find.text('Наличные').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('В долг').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Продать'));
    await tester.pumpAndSettle();

    expect(adapter.saleBodies.first['paymentMethod'], 'DEBT');
    expect(adapter.saleBodies.first.containsKey('cashAccountId'), isFalse);
  });
}
