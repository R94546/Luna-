import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/cash/data/cash_dto.dart';
import 'package:luna_app/features/cash/presentation/cash_screen.dart';
import 'package:luna_app/features/cash/presentation/widgets/expense_dialog.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<String?> expenseKeys = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == '/expenses') {
      expenseKeys.add(options.headers['Idempotency-Key'] as String?);
      return _json({'id': 'exp-1'}, status: 201);
    }

    return switch (options.path) {
      '/cash/accounts' => _json([
        {
          'id': 'acc-1',
          'name': 'Asosiy kassa',
          'type': 'CASH',
          'balance': '12400000',
          'isDefault': true,
        },
      ]),
      '/expense-categories' => _json([
        {'id': 'cat-1', 'name': 'Ijara', 'isSystem': true},
      ]),
      '/cash/summary' => _json({
        'dateFrom': '2026-08-01',
        'dateTo': '2026-08-31',
        'openingBalance': '10000000',
        'closingBalance': '12400000',
        'income': {'total': '3000000', 'bySale': '3000000', 'other': '0'},
        'outcome': {
          'total': '600000',
          'byCategory': [
            {'category': 'EXPENSE', 'name': 'Ijara', 'amount': '600000'},
          ],
        },
        'accounts': [
          {
            'id': 'acc-1',
            'name': 'Asosiy kassa',
            'type': 'CASH',
            'balance': '12400000',
            'isDefault': true,
          },
        ],
      }),
      '/cash/transactions' => _json({
        'items': [
          {
            'id': 't-1',
            'account': {'id': 'acc-1', 'name': 'Asosiy kassa'},
            'direction': 'IN',
            'category': 'INVESTMENT',
            'categoryName': 'Kirim',
            'amount': '200000',
            'occurredAt': '2026-08-20T00:00:00.000Z',
            'note': 'Vznos',
          },
        ],
        'meta': {'page': 1, 'limit': 50, 'total': 1, 'totalPages': 1},
        'summary': {'income': '200000', 'outcome': '0', 'net': '200000'},
      }),
      '/expenses' => _json({
        'items': [
          {
            'id': 'e-1',
            'category': {'id': 'cat-1', 'name': 'Ijara', 'isSystem': true},
            'amount': '600000',
            'spentAt': '2026-08-10T00:00:00.000Z',
            'note': 'Avgust',
          },
        ],
        'meta': {'page': 1, 'limit': 50, 'total': 1, 'totalPages': 1},
        'summary': {'totalAmount': '600000'},
      }),
      _ => _json(<String, dynamic>{}),
    };
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

Future<_FakeAdapter> _pump(WidgetTester tester, {Widget? widget}) async {
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
      child: MaterialApp(home: widget ?? const CashScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  group('сводка', () {
    testWidgets('показывает остатки и движение за период', (tester) async {
      await _pump(tester);

      expect(find.text('Остаток на начало'), findsOneWidget);
      expect(find.text('Остаток на конец'), findsOneWidget);
      expect(find.text('Приход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
    });

    /// Расходы раскрываются по своим категориям, а не одной строкой:
    /// владельцу нужно видеть, на что ушли деньги.
    testWidgets('расходы раскрыты по категориям', (tester) async {
      await _pump(tester);

      expect(find.text('Куда ушли деньги'), findsOneWidget);
      expect(find.text('Ijara'), findsOneWidget);
    });
  });

  group('журнал', () {
    testWidgets('показывает операции с направлением', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Журнал'));
      await tester.pumpAndSettle();

      expect(find.text('Vznos'), findsOneWidget);
      // Приход со знаком плюс — направление должно читаться с одного взгляда.
      expect(find.textContaining('+'), findsOneWidget);
    });
  });

  group('расходы', () {
    testWidgets('показывает список и итог', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Расходы'));
      await tester.pumpAndSettle();

      expect(find.text('Всего за период'), findsOneWidget);
      expect(find.text('Ijara'), findsOneWidget);
    });
  });

  group('ручная операция', () {
    /// Категорий продажи, зарплаты и расхода в ручной операции быть не
    /// должно: у каждой свой путь с первичным документом.
    test('доступны только внесение, изъятие и прочее', () {
      expect(ManualCategory.values.map((c) => c.value).toList(), [
        'INVESTMENT',
        'WITHDRAWAL',
        'OTHER',
      ]);
    });

    test('внесение приходует, изъятие списывает', () {
      expect(ManualCategory.investment.direction, CashDirection.income);
      expect(ManualCategory.withdrawal.direction, CashDirection.outcome);
    });
  });

  group('диалог расхода', () {
    testWidgets('расход уходит с ключом идемпотентности', (tester) async {
      final adapter = await _pump(
        tester,
        widget: const Scaffold(body: ExpenseDialog()),
      );

      await tester.enterText(find.byType(TextField).first, '75000');
      await tester.pumpAndSettle();

      // Открываем список категорий и выбираем единственную.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ijara').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Записать'));
      await tester.pumpAndSettle();

      expect(adapter.expenseKeys, hasLength(1));
      expect(adapter.expenseKeys.first, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    testWidgets('без категории запрос не уходит', (tester) async {
      final adapter = await _pump(
        tester,
        widget: const Scaffold(body: ExpenseDialog()),
      );

      await tester.enterText(find.byType(TextField).first, '75000');
      await tester.tap(find.text('Записать'));
      await tester.pumpAndSettle();

      expect(adapter.expenseKeys, isEmpty);
      expect(find.textContaining('Заполните'), findsOneWidget);
    });
  });
}
