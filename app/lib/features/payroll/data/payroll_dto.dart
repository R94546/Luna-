import 'package:freezed_annotation/freezed_annotation.dart';

part 'payroll_dto.freezed.dart';
part 'payroll_dto.g.dart';

enum PayrollPeriodStatus {
  @JsonValue('OPEN')
  open,
  @JsonValue('CLOSED')
  closed,
  @JsonValue('PAID')
  paid;

  String get label => switch (this) {
    PayrollPeriodStatus.open => 'Открыт',
    PayrollPeriodStatus.closed => 'Закрыт',
    PayrollPeriodStatus.paid => 'Выплачен',
  };

  /// Пока период открыт, его можно пересчитывать и править.
  bool get isEditable => this == PayrollPeriodStatus.open;
}

enum SalaryPaymentType {
  @JsonValue('ADVANCE')
  advance,
  @JsonValue('SALARY')
  salary,
  @JsonValue('BONUS')
  bonus;

  String get label => switch (this) {
    SalaryPaymentType.advance => 'Аванс',
    SalaryPaymentType.salary => 'Зарплата',
    SalaryPaymentType.bonus => 'Премия',
  };

  String get value => switch (this) {
    SalaryPaymentType.advance => 'ADVANCE',
    SalaryPaymentType.salary => 'SALARY',
    SalaryPaymentType.bonus => 'BONUS',
  };
}

/// Строка в списке периодов.
@freezed
class PeriodSummaryDto with _$PeriodSummaryDto {
  const factory PeriodSummaryDto({
    required String id,
    required String periodStart,
    required String periodEnd,
    required PayrollPeriodStatus status,
    required String totalAmount,
    @Default(0) int employeeCount,
    DateTime? closedAt,
  }) = _PeriodSummaryDto;

  factory PeriodSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$PeriodSummaryDtoFromJson(json);
}

/// Период с ведомостью.
@freezed
class PeriodDto with _$PeriodDto {
  const factory PeriodDto({
    required String periodId,
    required String periodStart,
    required String periodEnd,
    required PayrollPeriodStatus status,
    required String totalAmount,
    DateTime? closedAt,
    @Default([]) List<PayrollEntryDto> entries,
  }) = _PeriodDto;

  factory PeriodDto.fromJson(Map<String, dynamic> json) =>
      _$PeriodDtoFromJson(json);
}

/// Начисление одному сотруднику.
///
/// Аванс вычитается из выплаты, но не из начисления: заработал человек
/// столько, сколько заработал, аванс лишь часть этих денег, выданная
/// раньше. Обе величины показываются раздельно.
@freezed
class PayrollEntryDto with _$PayrollEntryDto {
  const factory PayrollEntryDto({
    required String id,
    required EmployeeRefDto employee,
    required String workAmount,
    required String bonus,
    required String deduction,
    required String totalAccrued,
    required String advancePaid,
    required String toPay,
    @Default(false) bool isPaid,
  }) = _PayrollEntryDto;

  factory PayrollEntryDto.fromJson(Map<String, dynamic> json) =>
      _$PayrollEntryDtoFromJson(json);
}

@freezed
class EmployeeRefDto with _$EmployeeRefDto {
  const factory EmployeeRefDto({
    required String id,
    @Default('') String fullName,
  }) = _EmployeeRefDto;

  factory EmployeeRefDto.fromJson(Map<String, dynamic> json) =>
      _$EmployeeRefDtoFromJson(json);
}

@freezed
class SalaryPaymentDto with _$SalaryPaymentDto {
  const factory SalaryPaymentDto({
    required String id,
    required EmployeeRefDto employee,
    required SalaryPaymentType type,
    required String amount,
    required DateTime paidAt,
    String? note,
    String? cashAccountId,
  }) = _SalaryPaymentDto;

  factory SalaryPaymentDto.fromJson(Map<String, dynamic> json) =>
      _$SalaryPaymentDtoFromJson(json);
}

@freezed
class SalaryPaymentsPageDto with _$SalaryPaymentsPageDto {
  const factory SalaryPaymentsPageDto({
    @Default([]) List<SalaryPaymentDto> items,
    @Default(AmountSummaryDto()) AmountSummaryDto summary,
  }) = _SalaryPaymentsPageDto;

  factory SalaryPaymentsPageDto.fromJson(Map<String, dynamic> json) =>
      _$SalaryPaymentsPageDtoFromJson(json);
}

@freezed
class AmountSummaryDto with _$AmountSummaryDto {
  const factory AmountSummaryDto({@Default('0') String totalAmount}) =
      _AmountSummaryDto;

  factory AmountSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$AmountSummaryDtoFromJson(json);
}
