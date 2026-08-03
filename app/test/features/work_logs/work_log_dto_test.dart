import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/work_logs/data/work_log_dto.dart';

/// Ответ бэкенда в том виде, в каком он описан в docs/03-api-design.md.
const _response = {
  'items': [
    {
      'id': 'c81a',
      'employee': {'id': '5a2f', 'fullName': 'Aziz Karimov'},
      'product': {'id': '9f3c', 'name': 'Sport-12', 'sku': 'SP-12'},
      'operation': {'id': '2e7b', 'name': 'Qolipga tortish'},
      'quantity': 24,
      'rate': '12000.00',
      'amount': '288000.00',
      'workDate': '2026-08-01T00:00:00.000Z',
      'status': 'PENDING',
      'source': 'TELEGRAM',
      'createdAt': '2026-08-01T14:32:10.000Z',
    },
  ],
  'meta': {'page': 1, 'limit': 20, 'total': 7, 'totalPages': 1},
  'summary': {'totalQuantity': 168, 'totalAmount': '2016000.00'},
};

void main() {
  test('разбирает страницу целиком', () {
    final page = WorkLogPageDto.fromJson(_response);

    expect(page.items, hasLength(1));
    expect(page.meta.total, 7);
    expect(page.summary.totalQuantity, 168);
    expect(page.summary.totalAmount, '2016000.00');
  });

  test('разбирает запись со всеми связями', () {
    final log = WorkLogPageDto.fromJson(_response).items.first;

    expect(log.employee.fullName, 'Aziz Karimov');
    expect(log.product.name, 'Sport-12');
    expect(log.product.sku, 'SP-12');
    expect(log.operation.name, 'Qolipga tortish');
    expect(log.quantity, 24);
    expect(log.status, WorkLogStatus.pending);
    expect(log.source, 'TELEGRAM');
  });

  /// Суммы остаются строками до самого форматирования: разбор в double
  /// вернул бы потерю копеек, ради избавления от которой сервер их
  /// строками и отдаёт.
  test('суммы остаются строками', () {
    final log = WorkLogPageDto.fromJson(_response).items.first;

    expect(log.rate, isA<String>());
    expect(log.amount, '288000.00');
  });

  test('разбирает все статусы', () {
    final sample = Map<String, dynamic>.from(
      (_response['items']! as List).first as Map,
    );

    for (final entry in {
      'PENDING': WorkLogStatus.pending,
      'APPROVED': WorkLogStatus.approved,
      'REJECTED': WorkLogStatus.rejected,
    }.entries) {
      final json = Map<String, dynamic>.from(_response)
        ..['items'] = [
          {...sample, 'status': entry.key},
        ];

      expect(WorkLogPageDto.fromJson(json).items.first.status, entry.value);
    }
  });

  test('значение статуса совпадает с ожидаемым сервером', () {
    expect(WorkLogStatus.pending.value, 'PENDING');
    expect(WorkLogStatus.approved.value, 'APPROVED');
    expect(WorkLogStatus.rejected.value, 'REJECTED');
  });

  /// Пустая выборка — обычное состояние в конце дня, когда всё разобрано.
  test('переваривает пустой список', () {
    final page = WorkLogPageDto.fromJson({
      'items': <dynamic>[],
      'meta': {'page': 1, 'limit': 20, 'total': 0, 'totalPages': 1},
      'summary': {'totalQuantity': 0, 'totalAmount': '0'},
    });

    expect(page.items, isEmpty);
    expect(page.summary.totalQuantity, 0);
  });

  test('необязательные поля могут отсутствовать', () {
    final log = WorkLogPageDto.fromJson({
      ..._response,
      'items': [
        {
          'id': 'x',
          'employee': {'id': 'e'},
          'product': {'id': 'p'},
          'operation': {'id': 'o'},
          'quantity': 1,
          'rate': '1',
          'amount': '1',
          'workDate': '2026-08-01T00:00:00.000Z',
          'status': 'APPROVED',
        },
      ],
    }).items.first;

    expect(log.note, isNull);
    expect(log.rejectReason, isNull);
    expect(log.source, 'MANUAL', reason: 'ручной ввод — значение по умолчанию');
  });

  test('разбирает результат пакетного подтверждения', () {
    final result = BulkApproveResultDto.fromJson({'approved': 3, 'skipped': 1});

    expect(result.approved, 3);
    expect(result.skipped, 1);
  });
}
