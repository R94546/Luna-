import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../l10n/app_localizations.dart';

part 'report_dto.freezed.dart';
part 'report_dto.g.dart';

/// Что выгружаем.
enum ReportType {
  finance('FINANCE'),
  sales('SALES'),
  payroll('PAYROLL'),
  production('PRODUCTION'),
  stock('STOCK');

  const ReportType(this.code);

  final String code;

  String label(L l10n) => switch (this) {
    ReportType.finance => l10n.reportTypeFinance,
    ReportType.sales => l10n.reportTypeSales,
    ReportType.payroll => l10n.reportTypePayroll,
    ReportType.production => l10n.reportTypeProduction,
    ReportType.stock => l10n.reportTypeStock,
  };

  /// Строка под названием: без неё пять пунктов списка выглядят одинаково.
  String description(L l10n) => switch (this) {
    ReportType.finance => l10n.reportTypeFinanceHint,
    ReportType.sales => l10n.reportTypeSalesHint,
    ReportType.payroll => l10n.reportTypePayrollHint,
    ReportType.production => l10n.reportTypeProductionHint,
    ReportType.stock => l10n.reportTypeStockHint,
  };
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
