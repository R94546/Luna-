import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/payroll/data/payroll_dto.dart';
import 'package:luna_app/features/payroll/presentation/widgets/pay_dialog.dart';

import '../../support/localized_app.dart';

/// Сервер, который запоминает заголовки каждой выплаты.
class _FakeAdapter implements HttpClientAdapter {
  final List<String?> paymentKeys = [];

  /// Сколько первых попыток выплаты уронить.
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

    paymentKeys.add(options.headers['Idempotency-Key'] as String?);

    if (paymentKeys.length <= failFirst) {
      return _json({
        'code': 'NETWORK',
        'message': 'Нет связи с сервером',
      }, status: 500);
    }

    return _json({'id': 'pay-1'}, status: 201);
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

const _entry = PayrollEntryDto(
  id: 'entry-1',
  employee: EmployeeRefDto(id: 'emp-1', fullName: 'Aziz Karimov'),
  workAmount: '400000',
  bonus: '0',
  deduction: '0',
  totalAccrued: '400000',
  advancePaid: '150000',
  toPay: '250000',
);

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
      child: localizedApp(
        const Scaffold(
          body: PayDialog(entry: _entry, periodId: 'period-1'),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('подставляет сумму к выплате', (tester) async {
    await _pump(tester);

    // Аванс уже вычтен сервером — платим остаток, а не всё начисление.
    expect(find.widgetWithText(TextField, '250000'), findsOneWidget);
  });

  testWidgets('выплата уходит с ключом идемпотентности', (tester) async {
    final adapter = await _pump(tester);

    await tester.tap(find.text('Выплатить'));
    await tester.pumpAndSettle();

    expect(adapter.paymentKeys, hasLength(1));
    expect(adapter.paymentKeys.first, isNotNull);
    expect(adapter.paymentKeys.first, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  /// Главный тест этого диалога.
  ///
  /// Связь оборвалась, человек жмёт «Выплатить» ещё раз. Повтор обязан
  /// уйти с ТЕМ ЖЕ ключом: иначе сервер посчитает его новой выплатой,
  /// и деньги уйдут из кассы дважды.
  testWidgets('повтор после ошибки идёт с тем же ключом', (tester) async {
    final adapter = await _pump(tester, failFirst: 1);

    await tester.tap(find.text('Выплатить'));
    await tester.pumpAndSettle();

    // Ошибку показали, диалог остался открыт.
    expect(find.textContaining('связи'), findsOneWidget);

    await tester.tap(find.text('Выплатить'));
    await tester.pumpAndSettle();

    expect(adapter.paymentKeys, hasLength(2));
    expect(
      adapter.paymentKeys.first,
      adapter.paymentKeys.last,
      reason: 'вторая попытка обязана переиспользовать ключ первой',
    );
  });

  testWidgets('без суммы запрос не уходит', (tester) async {
    final adapter = await _pump(tester);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('Выплатить'));
    await tester.pumpAndSettle();

    expect(adapter.paymentKeys, isEmpty);
    expect(find.textContaining('Укажите сумму'), findsOneWidget);
  });

  testWidgets('касса по умолчанию подставляется сама', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Asosiy kassa'), findsOneWidget);
  });
}
