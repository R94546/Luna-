import 'package:freezed_annotation/freezed_annotation.dart';

part 'report_dto.freezed.dart';
part 'report_dto.g.dart';

/// Что выгружаем.
enum ReportType {
  finance('FINANCE', 'Финансы', 'Приход, расход, категории, журнал кассы'),
  sales('SALES', 'Продажи', 'Каждая продажа, прибыль и разбивка по моделям'),
  payroll('PAYROLL', 'Зарплата', 'Начисления по сотрудникам и выплаты'),
  production(
    'PRODUCTION',
    'Выпуск',
    'Выработка по сотрудникам, операциям и дням',
  ),
  stock('STOCK', 'Склад', 'Остатки, сумма запаса и движения');

  const ReportType(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;
}

enum ReportFormat {
  xlsx('XLSX', 'Excel'),
  pdf('PDF', 'PDF');

  const ReportFormat(this.code, this.label);

  final String code;
  final String label;
}

@freezed
class ReportJobDto with _$ReportJobDto {
  const factory ReportJobDto({
    required String jobId,
    required String status,
    required String fileName,
    String? url,
  }) = _ReportJobDto;

  const ReportJobDto._();

  factory ReportJobDto.fromJson(Map<String, dynamic> json) =>
      _$ReportJobDtoFromJson(json);

  bool get isReady => status == 'READY';
  bool get isFailed => status == 'FAILED';
}
