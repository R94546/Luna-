import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/payroll/presentation/period_detail_screen.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 'OPEN'});

  String status;
  int calculateCalls = 0;
  int closeCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/calculate')) calculateCalls++;
    if (options.path.endsWith('/close')) {
      closeCalls++;
      status = 'CLOSED';
    }
    if (options.path == '/cash/accounts') return _json(<dynamic>[]);

    return _json({
      'periodId': 'period-1',
      'periodStart': '2026-08-01',
      'periodEnd': '2026-08-31',
      'status': status,
      'totalAmount': '854000',
      'entries': [
        {
          'id': 'entry-1',
          'employee': {'id': 'emp-1', 'fullName': 'Aziz Karimov'},
          'workAmount': '400000',
          'bonus': '50000',
          'deduction': '0',
          'totalAccrued': '450000',
          'advancePaid': '150000',
          'toPay': '300000',
          'isPaid': false,
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
  String status = 'OPEN',
}) async {
  final adapter = _FakeAdapter(status: status);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: PeriodDetailScreen(periodId: 'period-1')),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('показывает начисление и выплату раздельно', (tester) async {
    await _pump(tester);

    expect(find.text('Aziz Karimov'), findsOneWidget);
    // Аванс уменьшает выплату, но не начисление — обе цифры на экране.
    expect(find.text('Начислено'), findsOneWidget);
    expect(find.text('Выдан аванс'), findsOneWidget);

    // «К выплате» встречается дважды и это правильно: итог по периоду
    // в шапке и остаток по конкретному сотруднику в его строке.
    expect(find.text('К выплате'), findsNWidgets(2));
  });

  testWidgets('премия показывается отдельной строкой', (tester) async {
    await _pump(tester);

    expect(find.text('Премия'), findsOneWidget);
    // Удержания нет — пустую строку не рисуем.
    expect(find.text('Удержание'), findsNothing);
  });

  testWidgets('у открытого периода есть пересчёт и закрытие', (tester) async {
    await _pump(tester);

    expect(find.byTooltip('Пересчитать'), findsOneWidget);
    expect(find.byTooltip('Закрыть период'), findsOneWidget);
    expect(find.text('Премия / удержание'), findsOneWidget);
  });

  /// Закрытый период неприкосновенен: выработка уже привязана к нему,
  /// и правка начислений разошлась бы с выплаченными деньгами.
  testWidgets('у закрытого периода правки недоступны', (tester) async {
    await _pump(tester, status: 'CLOSED');

    expect(find.byTooltip('Пересчитать'), findsNothing);
    expect(find.byTooltip('Закрыть период'), findsNothing);
    expect(find.text('Премия / удержание'), findsNothing);
    // Выплатить по закрытому периоду всё ещё можно — деньги выдают после.
    expect(find.text('Выплатить'), findsOneWidget);
  });

  testWidgets('пересчёт отправляет запрос', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.byTooltip('Пересчитать'));
    await tester.pumpAndSettle();

    expect(adapter.calculateCalls, 1);
    expect(find.text('Пересчитано'), findsOneWidget);
  });

  /// Закрытие необратимо, поэтому спрашиваем подтверждение.
  testWidgets('закрытие требует подтверждения', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.byTooltip('Закрыть период'));
    await tester.pumpAndSettle();

    expect(find.text('Закрыть период?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(adapter.closeCalls, 0, reason: 'отмена не должна закрывать период');
  });

  testWidgets('подтверждённое закрытие уходит на сервер', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.byTooltip('Закрыть период'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Закрыть'));
    await tester.pumpAndSettle();

    expect(adapter.closeCalls, 1);
  });
}
