import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/features/work_logs/data/work_log_dto.dart';
import 'package:luna_app/features/work_logs/data/work_logs_api.dart';

void main() {
  group('параметры запроса', () {
    test('по умолчанию показываются ждущие подтверждения', () {
      const filter = WorkLogFilter();

      expect(filter.status, WorkLogStatus.pending);
      expect(filter.toQuery(1)['status'], 'PENDING');
    });

    /// «Все» — это отсутствие параметра, а не отдельное значение: сервер
    /// не знает статуса ALL и вернул бы ошибку валидации.
    test('«все» не передаёт статус вовсе', () {
      const filter = WorkLogFilter(status: null);

      expect(filter.toQuery(1).containsKey('status'), isFalse);
    });

    test('пустые фильтры не попадают в запрос', () {
      final query = const WorkLogFilter().toQuery(1);

      expect(query.containsKey('employeeId'), isFalse);
      expect(query.containsKey('dateFrom'), isFalse);
      expect(query.containsKey('dateTo'), isFalse);
    });

    test('даты приводятся к формату сервера', () {
      final filter = WorkLogFilter(
        dateFrom: DateTime.utc(2026, 8, 1, 15, 30),
        dateTo: DateTime.utc(2026, 8, 31),
      );

      final query = filter.toQuery(1);

      expect(query['dateFrom'], '2026-08-01');
      expect(query['dateTo'], '2026-08-31');
    });

    test('страница передаётся как есть', () {
      expect(const WorkLogFilter().toQuery(3)['page'], 3);
    });
  });

  group('copyWith', () {
    test('меняет один параметр, не трогая остальные', () {
      const filter = WorkLogFilter(
        status: WorkLogStatus.pending,
        employeeId: 'e-1',
      );

      final next = filter.copyWith(status: WorkLogStatus.approved);

      expect(next.status, WorkLogStatus.approved);
      expect(next.employeeId, 'e-1');
    });

    /// Сбросить фильтр в null через обычный copyWith нельзя — null там
    /// означает «не меняй». Отсюда отдельные флаги сброса.
    test('сбрасывает статус явным флагом', () {
      const filter = WorkLogFilter(status: WorkLogStatus.approved);

      expect(filter.copyWith(resetStatus: true).status, isNull);
      expect(filter.copyWith().status, WorkLogStatus.approved);
    });

    test('сбрасывает сотрудника и даты', () {
      final filter = WorkLogFilter(
        employeeId: 'e-1',
        dateFrom: DateTime.utc(2026, 8, 1),
        dateTo: DateTime.utc(2026, 8, 31),
      );

      final cleared = filter.copyWith(resetEmployee: true, resetDates: true);

      expect(cleared.employeeId, isNull);
      expect(cleared.dateFrom, isNull);
      expect(cleared.dateTo, isNull);
      expect(cleared.status, filter.status, reason: 'статус не сбрасывался');
    });
  });

  /// Фильтр служит ключом кэша Riverpod: без равенства по значению
  /// возврат к уже просмотренному набору перезапрашивал бы сервер.
  group('равенство', () {
    test('одинаковые фильтры равны и дают один хеш', () {
      const a = WorkLogFilter(status: WorkLogStatus.approved, employeeId: 'e');
      const b = WorkLogFilter(status: WorkLogStatus.approved, employeeId: 'e');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('разные фильтры не равны', () {
      const a = WorkLogFilter(status: WorkLogStatus.approved);
      const b = WorkLogFilter(status: WorkLogStatus.rejected);

      expect(a, isNot(b));
    });

    test('различает фильтры по датам', () {
      final a = WorkLogFilter(dateFrom: DateTime.utc(2026, 8, 1));
      final b = WorkLogFilter(dateFrom: DateTime.utc(2026, 8, 2));

      expect(a, isNot(b));
    });
  });

  group('hasExtraFilters', () {
    test('статус сам по себе дополнительным фильтром не считается', () {
      expect(const WorkLogFilter().hasExtraFilters, isFalse);
    });

    test('сотрудник и даты считаются', () {
      expect(const WorkLogFilter(employeeId: 'e').hasExtraFilters, isTrue);
      expect(
        WorkLogFilter(dateFrom: DateTime.utc(2026)).hasExtraFilters,
        isTrue,
      );
    });
  });
}
