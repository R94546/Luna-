import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/format/money.dart';
import 'package:luna_app/features/auth/domain/session.dart';
import 'package:luna_app/features/auth/domain/user_role.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/customers/presentation/customers_screen.dart';

import '../../support/localized_app.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.debt = '1200000'});

  final String debt;
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

    if (options.path == '/customers') {
      return _json({
        'items': [
          {'id': 'c-1', 'name': 'Bozor do‘kon', 'phone': '+998901112233'},
        ],
        'meta': {'page': 1, 'limit': 100, 'total': 1, 'totalPages': 1},
      });
    }

    return _json({
      'id': 'c-1',
      'name': 'Bozor do‘kon',
      'phone': '+998901112233',
      'salesCount': 4,
      'totalAmount': '5400000',
      'debt': debt,
      'activeOrders': 2,
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

Future<_FakeAdapter> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.owner,
  String debt = '1200000',
}) async {
  final adapter = _FakeAdapter(debt: debt);

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
      child: localizedApp(const CustomersScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

Future<void> _openCard(WidgetTester tester) async {
  await tester.tap(find.text('Bozor do‘kon'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('список показывает клиента с телефоном', (tester) async {
    await _pump(tester);

    expect(find.text('Bozor do‘kon'), findsOneWidget);
    expect(find.text('+998901112233'), findsOneWidget);
  });

  testWidgets('карточка показывает долг и заказы', (tester) async {
    await _pump(tester);
    await _openCard(tester);

    expect(find.text('Долг'), findsOneWidget);
    // Через Money.format, а не строкой: разряды разделены неразрывным
    // пробелом, и написанный руками обычный с ним не совпадёт.
    expect(find.text(Money.format('1200000')), findsOneWidget);
    expect(find.text('Активных заказов'), findsOneWidget);
  });

  /// Ноль, выделенный красным, читается как проблема, которой нет.
  testWidgets('нулевой долг не выделяется цветом ошибки', (tester) async {
    await _pump(tester, debt: '0');
    await _openCard(tester);

    final context = tester.element(find.byType(CustomersScreen));
    final value = tester.widget<Text>(find.text(Money.format('0')));

    expect(value.style?.color, isNot(Theme.of(context).colorScheme.error));
  });

  /// На клиента ссылаются продажи и заказы — архивирует только владелец.
  testWidgets('бухгалтер клиента не архивирует', (tester) async {
    await _pump(tester, role: UserRole.accountant);
    await _openCard(tester);

    expect(find.text('В архив'), findsNothing);
    expect(find.text('Изменить'), findsOneWidget);
  });

  testWidgets('владелец архивирует клиента', (tester) async {
    final adapter = await _pump(tester);
    await _openCard(tester);

    await tester.tap(find.text('В архив'));
    await tester.pumpAndSettle();

    expect(adapter.deleted, ['/customers/c-1']);
  });
}
