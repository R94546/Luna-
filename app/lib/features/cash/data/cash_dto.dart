import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../l10n/app_localizations.dart';

part 'cash_dto.freezed.dart';
part 'cash_dto.g.dart';

@freezed
class CashAccountDto with _$CashAccountDto {
  const factory CashAccountDto({
    required String id,
    required String name,
    @Default('CASH') String type,
    @Default('0') String balance,
    @Default(false) bool isDefault,
  }) = _CashAccountDto;

  factory CashAccountDto.fromJson(Map<String, dynamic> json) =>
      _$CashAccountDtoFromJson(json);
}

/// Направление движения денег.
enum CashDirection {
  @JsonValue('IN')
  income,
  @JsonValue('OUT')
  outcome;

  String get value => this == CashDirection.income ? 'IN' : 'OUT';
}

/// Категории, доступные для ручной операции.
///
/// Продажи, зарплаты и расхода здесь нет намеренно: у каждой свой путь,
/// который заводит первичный документ вместе с движением. Разреши их —
/// и в кассе появится зарплата, которой не соответствует ни одна выплата.
enum ManualCategory {
  investment('INVESTMENT', CashDirection.income),
  withdrawal('WITHDRAWAL', CashDirection.outcome),
  other('OTHER', CashDirection.outcome);

  const ManualCategory(this.value, this.direction);

  final String value;
  final CashDirection direction;

  String label(L l10n) => switch (this) {
    ManualCategory.investment => l10n.cashCategoryInvestment,
    ManualCategory.withdrawal => l10n.cashCategoryWithdrawal,
    ManualCategory.other => l10n.cashCategoryOther,
  };
}

@freezed
class CashTransactionDto with _$CashTransactionDto {
  const factory CashTransactionDto({
    required String id,
    required AccountRefDto account,
    required CashDirection direction,
    required String category,
    @Default('') String categoryName,
    required String amount,
    required DateTime occurredAt,
    String? note,
    String? refType,
  }) = _CashTransactionDto;

  factory CashTransactionDto.fromJson(Map<String, dynamic> json) =>
      _$CashTransactionDtoFromJson(json);
}

@freezed
class AccountRefDto with _$AccountRefDto {
  const factory AccountRefDto({required String id, @Default('') String name}) =
      _AccountRefDto;

  factory AccountRefDto.fromJson(Map<String, dynamic> json) =>
      _$AccountRefDtoFromJson(json);
}

@freezed
class CashJournalDto with _$CashJournalDto {
  const factory CashJournalDto({
    @Default([]) List<CashTransactionDto> items,
    @Default(JournalSummaryDto()) JournalSummaryDto summary,
  }) = _CashJournalDto;

  factory CashJournalDto.fromJson(Map<String, dynamic> json) =>
      _$CashJournalDtoFromJson(json);
}

@freezed
class JournalSummaryDto with _$JournalSummaryDto {
  const factory JournalSummaryDto({
    @Default('0') String income,
    @Default('0') String outcome,
    @Default('0') String net,
  }) = _JournalSummaryDto;

  factory JournalSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$JournalSummaryDtoFromJson(json);
}

@freezed
class CashSummaryDto with _$CashSummaryDto {
  const factory CashSummaryDto({
    required String openingBalance,
    required String closingBalance,
    required IncomeDto income,
    required OutcomeDto outcome,
    @Default([]) List<CashAccountDto> accounts,
  }) = _CashSummaryDto;

  factory CashSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$CashSummaryDtoFromJson(json);
}

@freezed
class IncomeDto with _$IncomeDto {
  const factory IncomeDto({
    @Default('0') String total,
    @Default('0') String bySale,
    @Default('0') String other,
  }) = _IncomeDto;

  factory IncomeDto.fromJson(Map<String, dynamic> json) =>
      _$IncomeDtoFromJson(json);
}

@freezed
class OutcomeDto with _$OutcomeDto {
  const factory OutcomeDto({
    @Default('0') String total,
    @Default([]) List<CategoryAmountDto> byCategory,
  }) = _OutcomeDto;

  factory OutcomeDto.fromJson(Map<String, dynamic> json) =>
      _$OutcomeDtoFromJson(json);
}

@freezed
class CategoryAmountDto with _$CategoryAmountDto {
  const factory CategoryAmountDto({
    @Default('') String category,
    @Default('') String name,
    @Default('0') String amount,
  }) = _CategoryAmountDto;

  factory CategoryAmountDto.fromJson(Map<String, dynamic> json) =>
      _$CategoryAmountDtoFromJson(json);
}

// ── Расходы ────────────────────────────────────────────────────────────────

@freezed
class ExpenseCategoryDto with _$ExpenseCategoryDto {
  const factory ExpenseCategoryDto({
    required String id,
    required String name,
    String? color,
    @Default(false) bool isSystem,
  }) = _ExpenseCategoryDto;

  factory ExpenseCategoryDto.fromJson(Map<String, dynamic> json) =>
      _$ExpenseCategoryDtoFromJson(json);
}

@freezed
class ExpenseDto with _$ExpenseDto {
  const factory ExpenseDto({
    required String id,
    required ExpenseCategoryDto category,
    required String amount,
    required DateTime spentAt,
    String? note,
    String? cashAccountId,
  }) = _ExpenseDto;

  factory ExpenseDto.fromJson(Map<String, dynamic> json) =>
      _$ExpenseDtoFromJson(json);
}

@freezed
class ExpensesPageDto with _$ExpensesPageDto {
  const factory ExpensesPageDto({
    @Default([]) List<ExpenseDto> items,
    @Default(ExpensesSummaryDto()) ExpensesSummaryDto summary,
  }) = _ExpensesPageDto;

  factory ExpensesPageDto.fromJson(Map<String, dynamic> json) =>
      _$ExpensesPageDtoFromJson(json);
}

@freezed
class ExpensesSummaryDto with _$ExpensesSummaryDto {
  const factory ExpensesSummaryDto({@Default('0') String totalAmount}) =
      _ExpensesSummaryDto;

  factory ExpensesSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$ExpensesSummaryDtoFromJson(json);
}
