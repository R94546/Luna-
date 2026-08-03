import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'work_log_dto.dart';

/// Фильтр списка выработки.
///
/// Отдельным типом, а не набором аргументов: он же служит ключом кэша
/// Riverpod, и для этого ему нужны равенство и хеш.
class WorkLogFilter {
  const WorkLogFilter({
    this.status = WorkLogStatus.pending,
    this.employeeId,
    this.dateFrom,
    this.dateTo,
  });

  /// null — все статусы.
  final WorkLogStatus? status;
  final String? employeeId;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  WorkLogFilter copyWith({
    WorkLogStatus? status,
    bool resetStatus = false,
    String? employeeId,
    bool resetEmployee = false,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool resetDates = false,
  }) {
    return WorkLogFilter(
      status: resetStatus ? null : (status ?? this.status),
      employeeId: resetEmployee ? null : (employeeId ?? this.employeeId),
      dateFrom: resetDates ? null : (dateFrom ?? this.dateFrom),
      dateTo: resetDates ? null : (dateTo ?? this.dateTo),
    );
  }

  bool get hasExtraFilters =>
      employeeId != null || dateFrom != null || dateTo != null;

  Map<String, dynamic> toQuery(int page) => {
    'page': page,
    'limit': 30,
    if (status != null) 'status': status!.value,
    if (employeeId != null) 'employeeId': employeeId,
    if (dateFrom != null) 'dateFrom': _date(dateFrom!),
    if (dateTo != null) 'dateTo': _date(dateTo!),
  };

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  @override
  bool operator ==(Object other) =>
      other is WorkLogFilter &&
      other.status == status &&
      other.employeeId == employeeId &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo;

  @override
  int get hashCode => Object.hash(status, employeeId, dateFrom, dateTo);
}

class WorkLogsApi {
  const WorkLogsApi(this._dio);

  final Dio _dio;

  Future<WorkLogPageDto> list(WorkLogFilter filter, {int page = 1}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/work-logs',
        queryParameters: filter.toQuery(page),
      );

      return WorkLogPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> approve(String id) async {
    try {
      await _dio.post<void>('/work-logs/$id/approve');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> reject(String id, String? reason) async {
    try {
      await _dio.post<void>(
        '/work-logs/$id/reject',
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Подтверждение пачкой.
  ///
  /// Утром мастер закрывает вчерашние отчёты одним нажатием — по одному
  /// это двадцать тапов, и половину он не сделает.
  Future<BulkApproveResultDto> bulkApprove(List<String> ids) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/work-logs/bulk-approve',
        data: {'ids': ids},
      );

      return BulkApproveResultDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
