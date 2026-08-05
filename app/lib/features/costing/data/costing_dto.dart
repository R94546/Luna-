import 'package:freezed_annotation/freezed_annotation.dart';

part 'costing_dto.freezed.dart';
part 'costing_dto.g.dart';

@freezed
class MaterialDto with _$MaterialDto {
  const factory MaterialDto({
    required String id,
    required String name,
    required String unit,
    @Default('0') String unitPrice,
  }) = _MaterialDto;

  factory MaterialDto.fromJson(Map<String, dynamic> json) =>
      _$MaterialDtoFromJson(json);
}

@freezed
class MaterialsPageDto with _$MaterialsPageDto {
  const factory MaterialsPageDto({@Default([]) List<MaterialDto> items}) =
      _MaterialsPageDto;

  factory MaterialsPageDto.fromJson(Map<String, dynamic> json) =>
      _$MaterialsPageDtoFromJson(json);
}

/// Строка расхода в форме калькулятора.
///
/// Либо ссылка на справочник, либо разовый материал: половина мелочи
/// покупается один раз под модель, и карточку ради неё никто не заведёт.
@freezed
class CostItemInput with _$CostItemInput {
  const factory CostItemInput({
    String? materialId,
    String? name,
    String? unit,
    String? unitPrice,
    required double quantity,
  }) = _CostItemInput;

  const CostItemInput._();

  Map<String, dynamic> toRequest() => {
    'materialId': ?materialId,
    'name': ?name,
    'unit': ?unit,
    'unitPrice': ?unitPrice,
    'quantity': quantity,
  };
}

@freezed
class CostBreakdownDto with _$CostBreakdownDto {
  const factory CostBreakdownDto({
    required String name,
    required String unit,
    required String quantity,
    required String unitPrice,
    required String total,
  }) = _CostBreakdownDto;

  factory CostBreakdownDto.fromJson(Map<String, dynamic> json) =>
      _$CostBreakdownDtoFromJson(json);
}

@freezed
class LaborBreakdownDto with _$LaborBreakdownDto {
  const factory LaborBreakdownDto({
    required String operation,
    required String rate,
  }) = _LaborBreakdownDto;

  factory LaborBreakdownDto.fromJson(Map<String, dynamic> json) =>
      _$LaborBreakdownDtoFromJson(json);
}

@freezed
class CalculationDto with _$CalculationDto {
  const factory CalculationDto({
    @Default('0') String materialsCost,
    @Default('0') String laborCost,
    @Default('0') String overheadCost,
    @Default('0') String totalCost,
    @Default('30') String marginPercent,
    @Default('0') String recommendedPrice,
    @Default('0') String profitPerUnit,

    /// Строки расхода с подставленными ценами — в том же порядке,
    /// в каком их прислали.
    @Default([]) List<CostBreakdownDto> items,
    @Default([]) List<LaborBreakdownDto> laborBreakdown,
  }) = _CalculationDto;

  factory CalculationDto.fromJson(Map<String, dynamic> json) =>
      _$CalculationDtoFromJson(json);
}

/// Сохранённый расчёт из списка.
@freezed
class SavedCalculationDto with _$SavedCalculationDto {
  const factory SavedCalculationDto({
    required String id,
    required String name,
    String? productId,
    @Default('0') String totalCost,
    @Default('0') String recommendedPrice,
    @Default(false) bool isApplied,
    required DateTime createdAt,
  }) = _SavedCalculationDto;

  factory SavedCalculationDto.fromJson(Map<String, dynamic> json) =>
      _$SavedCalculationDtoFromJson(json);
}

@freezed
class SavedCalculationsPageDto with _$SavedCalculationsPageDto {
  const factory SavedCalculationsPageDto({
    @Default([]) List<SavedCalculationDto> items,
  }) = _SavedCalculationsPageDto;

  factory SavedCalculationsPageDto.fromJson(Map<String, dynamic> json) =>
      _$SavedCalculationsPageDtoFromJson(json);
}
