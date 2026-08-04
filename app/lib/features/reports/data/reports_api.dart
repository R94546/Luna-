import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'report_dto.dart';

class ReportsApi {
  const ReportsApi(this._dio);

  final Dio _dio;

  /// Ставит отчёт в очередь. Файла ещё нет — вернётся `jobId`.
  Future<ReportJobDto> export({
    required ReportType type,
    required ReportFormat format,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/reports/export',
        data: {
          'type': type.code,
          'format': format.code,
          'dateFrom': _date(from),
          'dateTo': _date(to),
        },
      );

      return ReportJobDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<ReportJobDto> status(String jobId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/reports/$jobId');
      return ReportJobDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Скачивает готовый файл. `savePath` — куда положить на устройстве.
  Future<void> download(String jobId, String savePath) async {
    try {
      await _dio.download('/reports/$jobId/download', savePath);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
