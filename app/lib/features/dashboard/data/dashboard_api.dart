import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'dashboard_dto.dart';

/// Периоды, которыми мыслит владелец. Совпадают с enum'ом на бэкенде.
enum DashboardPeriod {
  week('week', 'Неделя'),
  month('month', 'Месяц'),
  quarter('quarter', 'Квартал'),
  year('year', 'Год');

  const DashboardPeriod(this.value, this.label);

  final String value;
  final String label;
}

class DashboardApi {
  const DashboardApi(this._dio);

  final Dio _dio;

  /// Весь главный экран одним запросом.
  ///
  /// Бэкенд собирает его сам именно для этого: пять параллельных запросов
  /// на плохой связи дают пять шансов показать наполовину пустой экран.
  Future<DashboardDto> load(DashboardPeriod period) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/analytics/dashboard',
        queryParameters: {'period': period.value},
      );

      return DashboardDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
