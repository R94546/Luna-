import '../../../l10n/app_localizations.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'work_log_dto.freezed.dart';
part 'work_log_dto.g.dart';

/// Статус записи выработки. Совпадает с enum'ом бэкенда.
enum WorkLogStatus {
  @JsonValue('PENDING')
  pending,
  @JsonValue('APPROVED')
  approved,
  @JsonValue('REJECTED')
  rejected;

  String label(L l10n) => switch (this) {
    WorkLogStatus.pending => l10n.workLogsPending,
    WorkLogStatus.approved => l10n.workLogsApproved,
    WorkLogStatus.rejected => l10n.workLogsRejected,
  };

  /// Значение для параметра запроса.
  String get value => switch (this) {
    WorkLogStatus.pending => 'PENDING',
    WorkLogStatus.approved => 'APPROVED',
    WorkLogStatus.rejected => 'REJECTED',
  };
}

@freezed
class WorkLogDto with _$WorkLogDto {
  const factory WorkLogDto({
    required String id,
    required RefDto employee,
    required RefDto product,
    required RefDto operation,
    required int quantity,
    required String rate,
    required String amount,
    required DateTime workDate,
    required WorkLogStatus status,
    @Default('MANUAL') String source,
    String? note,
    String? rejectReason,
    DateTime? createdAt,
  }) = _WorkLogDto;

  factory WorkLogDto.fromJson(Map<String, dynamic> json) =>
      _$WorkLogDtoFromJson(json);
}

/// Ссылка на сущность: сервер отдаёт вложенным объектом, чтобы клиенту
/// не приходилось догружать имена отдельными запросами.
@freezed
class RefDto with _$RefDto {
  const factory RefDto({
    required String id,
    @Default('') String fullName,
    @Default('') String name,
    @Default('') String sku,
  }) = _RefDto;

  factory RefDto.fromJson(Map<String, dynamic> json) => _$RefDtoFromJson(json);
}

@freezed
class PageMetaDto with _$PageMetaDto {
  const factory PageMetaDto({
    @Default(1) int page,
    @Default(20) int limit,
    @Default(0) int total,
    @Default(1) int totalPages,
  }) = _PageMetaDto;

  factory PageMetaDto.fromJson(Map<String, dynamic> json) =>
      _$PageMetaDtoFromJson(json);
}

/// Итоги по всей выборке с учётом фильтров, а не по видимой странице:
/// мастеру нужна сумма за день целиком, а не за двадцать строк.
@freezed
class WorkLogSummaryDto with _$WorkLogSummaryDto {
  const factory WorkLogSummaryDto({
    @Default(0) int totalQuantity,
    @Default('0') String totalAmount,
  }) = _WorkLogSummaryDto;

  factory WorkLogSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$WorkLogSummaryDtoFromJson(json);
}

@freezed
class WorkLogPageDto with _$WorkLogPageDto {
  const factory WorkLogPageDto({
    @Default([]) List<WorkLogDto> items,
    required PageMetaDto meta,
    required WorkLogSummaryDto summary,
  }) = _WorkLogPageDto;

  factory WorkLogPageDto.fromJson(Map<String, dynamic> json) =>
      _$WorkLogPageDtoFromJson(json);
}

/// Ответ пакетного подтверждения.
@freezed
class BulkApproveResultDto with _$BulkApproveResultDto {
  const factory BulkApproveResultDto({
    @Default(0) int approved,
    @Default(0) int skipped,
  }) = _BulkApproveResultDto;

  factory BulkApproveResultDto.fromJson(Map<String, dynamic> json) =>
      _$BulkApproveResultDtoFromJson(json);
}
