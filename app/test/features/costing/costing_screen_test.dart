import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/auth/presentation/providers/session_provider.dart';
import 'package:luna_app/features/catalog/data/catalog_dto.dart';
import 'package:luna_app/features/costing/data/costing_dto.dart';
import 'package:luna_app/features/costing/presentation/costing_screen.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> calculations = [];
  Map<String, dynamic>? saved;
  final List<String> applied = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/materials') {
      return _json({
        'items': [
          {'id': 'm-1', 'name': 'Кожа', 'unit': 'дм²', 'unitPrice': '34000.00'},
        ],
      });
    }

    if (options.path == '/products') {
      return _json({
        'items': [
          {'id': 'p-1', 'sku': 'ZM-04', 'name': 'Ботинки Qish-4'},
        ],
      });
    }

    if (options.path == '/costing/calculate') {
      calculations.add(options.data as Map<String, dynamic>);
      return _json({
        'materialsCost': '85000.00',
        'laborCost': '33000.00',
        'overheadCost': '0.00',
        'totalCost': '118000.00',
        'marginPercent': '30.00',
        'recommendedPrice': '153400.00',
        'profitPerUnit': '35400.00',
        'items': [
          {
            'name': 'Кожа',
            'unit': 'дм²',
            'quantity': '2.500',
            'unitPrice': '34000.00',
            'total': '85000.00',
          },
        ],
        'laborBreakdown': [
          {'operation': 'Пошив', 'rate': '18000.00'},
          {'operation': 'Упаковка', 'rate': '15000.00'},
        ],
      });
    }

    if (options.path == '/costing') {
      saved = options.data as Map<String, dynamic>;
      return _json({
        'id': 'c-1',
        'name': 'Расчёт',
        'totalCost': '118000.00',
        'recommendedPrice': '153400.00',
        'isApplied': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    if (options.path.endsWith('/apply')) {
      applied.add(options.path);
      return _json({'ok': true});
    }

    return _json({'items': <Object>[]});
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

Future<_FakeAdapter> _pump(WidgetTester tester) async {
  final adapter = _FakeAdapter();

  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test',
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;

  // Экран длинный: список материалов, накладные, ползунок и итог.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: CostingScreen()),
    ),
  );

  await tester.pumpAndSettle();
  return adapter;
}

/// Ищет сумму на экране по цифрам.
///
/// Разряды в приложении разделены неразрывным пробелом, и искать
/// «118 000» с обычным пробелом бессмысленно — совпадения не будет
/// при полностью правильном экране.
Finder _money(String digits) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits),
);

/// Добавляет строку расхода материалом из справочника.
Future<void> _addLeather(WidgetTester tester, {String quantity = '2.5'}) async {
  await tester.tap(find.text('Добавить'));
  await tester.pumpAndSettle();

  await tester.tap(find.byType(DropdownButtonFormField<MaterialDto>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Кожа').last);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, '1'), quantity);
  await tester.tap(find.text('Добавить').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('пустой расчёт ничего не запрашивает', (tester) async {
    final adapter = await _pump(tester);

    expect(adapter.calculations, isEmpty);
    expect(find.textContaining('Пока пусто'), findsOneWidget);
  });

  testWidgets('материал уходит без цены — её знает сервер', (tester) async {
    final adapter = await _pump(tester);

    await _addLeather(tester);

    expect(adapter.calculations, hasLength(1));
    final items = adapter.calculations.first['items'] as List<dynamic>;
    final item = items.first as Map<String, dynamic>;

    expect(item['materialId'], 'm-1');
    expect(item['quantity'], 2.5);
    // Цену подставит справочник: прислать свою — значит посчитать
    // себестоимость по цене, которой нет.
    expect(item.containsKey('unitPrice'), isFalse);
  });

  testWidgets('показывает итог и откуда взялась работа', (tester) async {
    await _pump(tester);
    await _addLeather(tester);

    expect(find.text('Себестоимость'), findsWidgets);
    expect(_money('118000'), findsWidgets);
    // Разбивка объясняет цифру работы — она сложена из расценок.
    expect(find.textContaining('Пошив'), findsOneWidget);
  });

  testWidgets('наценка меняет цену без похода на сервер', (tester) async {
    final adapter = await _pump(tester);
    await _addLeather(tester);

    final before = adapter.calculations.length;
    expect(_money('153400'), findsWidgets);

    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pumpAndSettle();

    // Цена пересчиталась на месте: наценка — это умножение готовой
    // себестоимости, и запрос ради него не нужен.
    expect(adapter.calculations.length, before);
    expect(_money('153400'), findsNothing);
  });

  testWidgets('сохранение предлагает записать в модель', (tester) async {
    final adapter = await _pump(tester);
    await _addLeather(tester);

    // Выбор модели — иначе записывать некуда, и вопроса быть не должно.
    await tester.tap(find.byType(DropdownButtonFormField<ProductDto?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ботинки Qish-4').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сохранить расчёт'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Зимние');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pumpAndSettle();

    expect(adapter.saved?['name'], 'Зимние');
    expect(adapter.saved?['productId'], 'p-1');
    expect(find.text('Записать в модель?'), findsOneWidget);

    await tester.tap(find.text('Записать'));
    await tester.pumpAndSettle();

    expect(adapter.applied, ['/costing/c-1/apply']);
  });
}
