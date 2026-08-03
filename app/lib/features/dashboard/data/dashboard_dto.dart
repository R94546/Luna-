import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard_dto.freezed.dart';
part 'dashboard_dto.g.dart';

@freezed
class DashboardDto with _$DashboardDto {
  const factory DashboardDto({
    required PeriodDto period,
    required MetricDto revenue,
    required MetricDto grossProfit,
    required MetricDto netProfit,
    required MetricDto expenses,
    required MetricDto salaries,
    required String cashBalance,
    required String salaryDebt,
    required int unitsProduced,
    required int unitsSold,
    required AlertsDto alerts,
    @Default([]) List<ChartPointDto> revenueChart,
    @Default([]) List<TopProductDto> topProducts,
  }) = _DashboardDto;

  factory DashboardDto.fromJson(Map<String, dynamic> json) =>
      _$DashboardDtoFromJson(json);
}

@freezed
class PeriodDto with _$PeriodDto {
  const factory PeriodDto({
    required String from,
    required String to,
    required String label,
  }) = _PeriodDto;

  factory PeriodDto.fromJson(Map<String, dynamic> json) =>
      _$PeriodDtoFromJson(json);
}

/// Показатель с динамикой.
///
/// `changePercent` приходит `null`, когда прошлый период был нулевым:
/// рост с нуля процентами не выражается. Тип обязан быть nullable,
/// иначе прочерк превратится в «0%» — то есть в неправду.
@freezed
class MetricDto with _$MetricDto {
  const factory MetricDto({
    required String value,
    String? previous,
    double? changePercent,
  }) = _MetricDto;

  factory MetricDto.fromJson(Map<String, dynamic> json) =>
      _$MetricDtoFromJson(json);
}

@freezed
class AlertsDto with _$AlertsDto {
  const factory AlertsDto({
    @Default(0) int pendingWorkLogs,
    @Default(0) int lowStockProducts,
    @Default(0) int overdueOrders,
  }) = _AlertsDto;

  factory AlertsDto.fromJson(Map<String, dynamic> json) =>
      _$AlertsDtoFromJson(json);
}

@freezed
class ChartPointDto with _$ChartPointDto {
  const factory ChartPointDto({
    required String date,
    required String revenue,
    required String profit,
  }) = _ChartPointDto;

  factory ChartPointDto.fromJson(Map<String, dynamic> json) =>
      _$ChartPointDtoFromJson(json);
}

@freezed
class TopProductDto with _$TopProductDto {
  const factory TopProductDto({
    required String id,
    required String name,
    @Default('') String sku,
    @Default(0) int unitsSold,
    @Default('0') String revenue,
    @Default('0') String profit,
  }) = _TopProductDto;

  factory TopProductDto.fromJson(Map<String, dynamic> json) =>
      _$TopProductDtoFromJson(json);
}
