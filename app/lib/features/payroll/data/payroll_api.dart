import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/idempotency.dart';
import 'payroll_dto.dart';

class PayrollApi {
  const PayrollApi(this._dio);

  final Dio _dio;

  Future<List<PeriodSummaryDto>> periods() async {
    try {
      final response = await _dio.get<List<dynamic>>('/payroll/periods');

      return (response.data ?? [])
          .map((e) => PeriodSummaryDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<PeriodDto> period(String id) => _period('/payroll/periods/$id');

  Future<PeriodDto> createPeriod({
    required String periodStart,
    required String periodEnd,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/payroll/periods',
        data: {'periodStart': periodStart, 'periodEnd': periodEnd},
      );

      return PeriodDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Пересчёт. Идемпотентен на бэкенде — суммы выводятся заново, а не
  /// накапливаются, поэтому нажать можно сколько угодно раз.
  Future<PeriodDto> calculate(String id) =>
      _post('/payroll/periods/$id/calculate');

  Future<PeriodDto> close(String id) => _post('/payroll/periods/$id/close');

  Future<PeriodDto> updateEntry(
    String entryId, {
    String? bonus,
    String? deduction,
  }) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/payroll/entries/$entryId',
        data: {'bonus': ?bonus, 'deduction': ?deduction},
      );

      return PeriodDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Выплата. Единственный путь зарплаты в кассу.
  ///
  /// Ключ идемпотентности приходит снаружи: повтор после обрыва связи
  /// обязан уйти с тем же ключом, иначе в кассе окажутся две выплаты.
  Future<void> pay({
    required String employeeId,
    required SalaryPaymentType type,
    required String amount,
    required String paidAt,
    required String cashAccountId,
    required IdempotencyKey key,
    String? payrollEntryId,
    String? note,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/salary-payments',
        data: {
          'employeeId': employeeId,
          'type': type.value,
          'amount': amount,
          'paidAt': paidAt,
          'cashAccountId': cashAccountId,
          'payrollEntryId': ?payrollEntryId,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        options: key.options,
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<SalaryPaymentsPageDto> payments({String? employeeId}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/salary-payments',
        queryParameters: {'limit': 50, 'employeeId': ?employeeId},
      );

      return SalaryPaymentsPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<PeriodDto> _period(String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      return PeriodDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<PeriodDto> _post(String path) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path);
      return PeriodDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
