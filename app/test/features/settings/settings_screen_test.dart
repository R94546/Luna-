import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/domain/session.dart';
import 'package:luna_app/features/auth/domain/user_role.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/settings/presentation/settings_screen.dart';

import '../../support/localized_app.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.rejectPassword = false});

  /// Сервер отвергает текущий пароль.
  final bool rejectPassword;

  final List<Map<String, dynamic>> passwordCalls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Настройки показывают значок непрочитанных, поэтому лента
    // запрашивается при каждом открытии экрана.
    if (options.path == '/notifications') {
      return _json({'items': <Object>[], 'unread': 0});
    }

    if (options.path == '/auth/password') {
      passwordCalls.add(options.data as Map<String, dynamic>);

      if (rejectPassword) {
        return _json({
          'code': 'INVALID_CREDENTIALS',
          'message': 'Неверный пароль',
        }, status: 400);
      }
    }

    return _json({'ok': true});
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
  @override
  Future<Session?> build() async => const Session(
    userId: 'u',
    fullName: 'Rustam',
    phone: '+998901234567',
    role: UserRole.owner,
    companyName: 'Luna',
  );
}

Future<_FakeAdapter> _pump(
  WidgetTester tester, {
  bool rejectPassword = false,
}) async {
  final adapter = _FakeAdapter(rejectPassword: rejectPassword);

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
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: localizedApp(const SettingsScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

Future<void> _fillPasswords(
  WidgetTester tester, {
  required String current,
  required String next,
  required String repeat,
}) async {
  await tester.tap(find.text('Сменить пароль'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), current);
  await tester.enterText(fields.at(1), next);
  await tester.enterText(fields.at(2), repeat);

  await tester.tap(find.text('Сменить'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('показывает, под кем вошли', (tester) async {
    await _pump(tester);

    expect(find.text('Rustam'), findsOneWidget);
    expect(find.textContaining('Владелец'), findsOneWidget);
    expect(find.text('Luna'), findsOneWidget);
  });

  testWidgets('пароль меняется с текущим и новым', (tester) async {
    final adapter = await _pump(tester);

    await _fillPasswords(
      tester,
      current: 'old-pass',
      next: 'new-pass',
      repeat: 'new-pass',
    );

    expect(adapter.passwordCalls, [
      {'currentPassword': 'old-pass', 'newPassword': 'new-pass'},
    ]);
    expect(find.text('Пароль изменён'), findsOneWidget);
  });

  /// Опечатка в повторе — повод не гонять запрос: сервер второго поля
  /// всё равно не видит и подтвердит смену на то, что человек не хотел.
  testWidgets('несовпадающие пароли не уходят на сервер', (tester) async {
    final adapter = await _pump(tester);

    await _fillPasswords(
      tester,
      current: 'old-pass',
      next: 'new-pass',
      repeat: 'new-pas',
    );

    expect(adapter.passwordCalls, isEmpty);
    expect(find.text('Пароли не совпадают'), findsOneWidget);
  });

  testWidgets('отказ сервера показывается в форме', (tester) async {
    await _pump(tester, rejectPassword: true);

    await _fillPasswords(
      tester,
      current: 'wrong',
      next: 'new-pass',
      repeat: 'new-pass',
    );

    expect(find.text('Неверный пароль'), findsOneWidget);
    // Диалог остался открыт — исправлять пароль негде, если его закрыть.
    expect(find.text('Сменить'), findsOneWidget);
  });

  testWidgets('выход спрашивает подтверждение', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();

    expect(find.textContaining('войти заново'), findsOneWidget);
  });
}
