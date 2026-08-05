import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/reports/presentation/reports_screen.dart';

import '../../support/localized_app.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Сервер, который отдаёт файл не сразу: первый опрос — PENDING.
///
/// Именно это и проверяем: экран обязан дождаться готовности, а не
/// скачивать по первому ответу.
class _FakeAdapter implements HttpClientAdapter {
  final List<String> calls = [];
  int statusChecks = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');

    if (options.path == '/reports/export') {
      exported = options.data as Map<String, dynamic>;
      return _json({
        'jobId': 'job-1',
        'status': 'PENDING',
        'fileName': 'sales.xlsx',
      });
    }

    if (options.path == '/reports/job-1') {
      statusChecks++;
      return _json({
        'jobId': 'job-1',
        'status': statusChecks < 2 ? 'PENDING' : 'READY',
        'fileName': 'sales.xlsx',
        'url': '/reports/job-1/download',
      });
    }

    return ResponseBody.fromBytes(
      utf8.encode('file-content'),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
      },
    );
  }

  Map<String, dynamic>? exported;

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

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.directory);

  final String directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('luna-reports-test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDown(() {
    // Windows держит файл занятым ещё мгновение после закрытия потока,
    // и падать из-за уборки временной папки тест не должен.
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // Останется в системном temp — его чистит сама система.
    }
  });

  /// Прокрутить выгрузку до конца.
  ///
  /// `pumpAndSettle` здесь не годится дважды. Во-первых, пока идёт опрос,
  /// на кнопке крутится индикатор — кадры планируются бесконечно, и
  /// «успокоиться» нечему. Во-вторых, файл пишется настоящим вводом-выводом,
  /// а он в тестовом времени не идёт: нужен `runAsync` с реальными паузами.
  Future<void> runExport(WidgetTester tester) async {
    await tester.tap(find.text('Выгрузить'));

    for (var i = 0; i < 12; i++) {
      // Тестовое время двигает опрос статуса…
      await tester.pump(const Duration(milliseconds: 600));
      // …а настоящее — запись файла на диск.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    await tester.pump();
  }

  Future<_FakeAdapter> pump(WidgetTester tester) async {
    final adapter = _FakeAdapter();

    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test',
        validateStatus: (status) => status != null && status < 400,
      ),
    )..httpClientAdapter = adapter;

    // Экран длинный: пять типов, период, формат и кнопка. В стандартные
    // 800×600 кнопка не помещается, и тест бы её «не нашёл».
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: localizedApp(const ReportsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('по умолчанию — финансы за этот месяц в Excel', (tester) async {
    final adapter = await pump(tester);

    await runExport(tester);

    final now = DateTime.now();
    expect(adapter.exported?['type'], 'FINANCE');
    expect(adapter.exported?['format'], 'XLSX');
    expect(
      adapter.exported?['dateFrom'],
      '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
    );
  });

  testWidgets('дожидается готовности и скачивает файл', (tester) async {
    final adapter = await pump(tester);

    await runExport(tester);

    // Первый опрос вернул PENDING — значит скачивание пошло после второго.
    expect(adapter.statusChecks, greaterThanOrEqualTo(2));
    expect(adapter.calls, contains('GET /reports/job-1/download'));

    expect(find.text('Готово'), findsOneWidget);
    expect(
      File('${temp.path}${Platform.pathSeparator}sales.xlsx').existsSync(),
      isTrue,
    );

    // Файл открывается только по кнопке: сам он ничего не запускает.
    expect(find.text('Открыть'), findsOneWidget);
  });

  testWidgets('выбранный тип и формат уходят на сервер', (tester) async {
    final adapter = await pump(tester);

    await tester.tap(find.text('Зарплата'));
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    await runExport(tester);

    expect(adapter.exported?['type'], 'PAYROLL');
    expect(adapter.exported?['format'], 'PDF');
  });
}
