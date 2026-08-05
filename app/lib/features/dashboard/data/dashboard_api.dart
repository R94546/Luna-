import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import 'dashboard_dto.dart';

/// Периоды, которыми мыслит владелец. Совпадают с enum'ом на бэкенде.
enum DashboardPeriod {
  week('week'),
  month('month'),
  quarter('quarter'),
  year('year');

  const DashboardPeriod(this.value);

  final String value;

  String label(L l10n) => switch (this) {
    DashboardPeriod.week => l10n.periodWeek,
    DashboardPeriod.month => l10n.periodMonth,
    DashboardPeriod.quarter => l10n.periodQuarter,
    DashboardPeriod.year => l10n.periodYear,
  };
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
