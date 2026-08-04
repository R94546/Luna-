import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/orders/presentation/order_detail_screen.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.status = 'NEW',
    this.transitions = const ['IN_PROGRESS', 'CANCELLED'],
  });

  String status;
  List<String> transitions;

  final List<Map<String, dynamic>> statusCalls = [];
  Map<String, dynamic>? progressCall;

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

    if (options.path.endsWith('/status')) {
      statusCalls.add(options.data as Map<String, dynamic>);
      status = statusCalls.last['status'] as String;
      transitions = const [];
    }

    if (options.path.endsWith('/progress')) {
      progressCall = options.data as Map<String, dynamic>;
    }

    return _json({
      'id': 'order-1',
      'orderNumber': 14,
      'status': status,
      'availableTransitions': transitions,
      'customer': {'id': 'c-1', 'name': 'Magazin «Olamon»'},
      'dueDate': '2026-08-20',
      'isOverdue': false,
      'totalAmount': '13500000',
      'prepaidAmount': '5000000',
      'debt': '8500000',
      'progress': {'ordered': 30, 'produced': 18, 'percent': 60},
      'items': [
        {
          'id': 'item-1',
          'product': {'id': 'p-1', 'name': 'Sport-12', 'sku': 'SP-12'},
          'quantity': 30,
          'producedQuantity': 18,
          'unitPrice': '450000',
          'total': '13500000',
        },
      ],
    });
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

Future<_FakeAdapter> _pump(
  WidgetTester tester, {
  String status = 'NEW',
  List<String> transitions = const ['IN_PROGRESS', 'CANCELLED'],
}) async {
  final adapter = _FakeAdapter(status: status, transitions: transitions);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: OrderDetailScreen(orderId: 'order-1')),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

/// Кнопка внутри диалога.
///
/// На экране за диалогом есть своя «Выдать», и поиск по всему дереву
/// находит обе. Ограничиваем область диалогом.
Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);

void main() {
  testWidgets('показывает заказ, долг и готовность', (tester) async {
    await _pump(tester);

    expect(find.text('Заказ №14'), findsOneWidget);
    expect(find.text('Magazin «Olamon»'), findsOneWidget);
    expect(find.text('Долг'), findsOneWidget);
    // Готовность считает сервер — 18 из 30 это 60%.
    expect(find.text('60%'), findsOneWidget);
    expect(find.textContaining('18 из 30'), findsOneWidget);
  });

  /// Кнопки переходов берутся из ответа сервера. Клиент не решает,
  /// что можно: иначе автомат статусов оказался бы в двух местах.
  testWidgets('кнопки берутся из availableTransitions', (tester) async {
    await _pump(tester, transitions: const ['IN_PROGRESS', 'CANCELLED']);

    expect(find.text('В работе'), findsOneWidget);
    expect(find.text('Отменить заказ'), findsOneWidget);
    expect(find.text('Готов'), findsNothing);
    expect(find.text('Выдать'), findsNothing);
  });

  testWidgets('у терминального статуса переходов нет', (tester) async {
    await _pump(tester, status: 'ISSUED', transitions: const []);

    expect(find.text('Выдать'), findsNothing);
    expect(find.text('Отменить заказ'), findsNothing);
    // Отмечать произведённое в выданном заказе тоже незачем.
    expect(find.text('Отметить произведённое'), findsNothing);
  });

  testWidgets('обычный переход уходит сразу, без диалога', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('В работе'));
    await tester.pumpAndSettle();

    expect(adapter.statusCalls, hasLength(1));
    expect(adapter.statusCalls.first['status'], 'IN_PROGRESS');
    expect(adapter.statusCalls.first['createSale'], false);
  });

  /// Выдача — единственный переход с последствиями за пределами заказа:
  /// товар уходит со склада, и по желанию оформляется продажа.
  testWidgets('выдача спрашивает про продажу', (tester) async {
    final adapter = await _pump(
      tester,
      status: 'READY',
      transitions: const ['ISSUED', 'CANCELLED'],
    );

    await tester.tap(find.text('Выдать'));
    await tester.pumpAndSettle();

    expect(find.text('Выдать заказ №14'), findsOneWidget);
    expect(find.text('Оформить продажу'), findsOneWidget);
    expect(adapter.statusCalls, isEmpty, reason: 'запрос ждёт подтверждения');
  });

  testWidgets('выдача с продажей передаёт кассу и оплату', (tester) async {
    final adapter = await _pump(
      tester,
      status: 'READY',
      transitions: const ['ISSUED', 'CANCELLED'],
    );

    await tester.tap(find.text('Выдать'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton('Выдать'));
    await tester.pumpAndSettle();

    expect(adapter.statusCalls, hasLength(1));
    final call = adapter.statusCalls.first;

    expect(call['status'], 'ISSUED');
    expect(call['createSale'], true);
    expect(call['cashAccountId'], 'acc-1');
    // Подставляется долг по заказу — обычно платят именно его.
    expect(call['paidAmount'], '8500000');
  });

  testWidgets('выдачу можно провести без продажи', (tester) async {
    final adapter = await _pump(
      tester,
      status: 'READY',
      transitions: const ['ISSUED'],
    );

    await tester.tap(find.text('Выдать'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.tap(_dialogButton('Выдать'));
    await tester.pumpAndSettle();

    expect(adapter.statusCalls.first['createSale'], false);
    expect(adapter.statusCalls.first['cashAccountId'], isNull);
  });

  testWidgets('отметка о произведённом уходит по позициям', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('Отметить произведённое'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(adapter.progressCall, isNotNull);
    expect(adapter.progressCall!['items'], [
      {'itemId': 'item-1', 'producedQuantity': 25},
    ]);
  });
}
