import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_dto.freezed.dart';
part 'catalog_dto.g.dart';

@freezed
class ProductDto with _$ProductDto {
  const factory ProductDto({
    required String id,
    required String sku,
    required String name,
    String? category,
    @Default('0') String salePrice,
    @Default('0') String costPrice,
    @Default(0) int stockQuantity,
    @Default(0) int minStockLevel,
    @Default(false) bool isLowStock,
    @Default(true) bool isActive,
  }) = _ProductDto;

  factory ProductDto.fromJson(Map<String, dynamic> json) =>
      _$ProductDtoFromJson(json);
}

@freezed
class ProductsPageDto with _$ProductsPageDto {
  const factory ProductsPageDto({@Default([]) List<ProductDto> items}) =
      _ProductsPageDto;

  factory ProductsPageDto.fromJson(Map<String, dynamic> json) =>
      _$ProductsPageDtoFromJson(json);
}

/// Типы движения склада, доступные для ручного ввода.
///
/// Списка из семи значений схемы здесь нет намеренно: `SALE_OUT`,
/// `ORDER_OUT` и `PRODUCTION_IN` заводит не человек, а продажа, выдача
/// заказа и подтверждённая выработка. Дай их руками — и остаток разойдётся
/// с документами, которые его двигали.
enum MovementType {
  purchaseIn('PURCHASE_IN', 'Закупка'),
  returnIn('RETURN_IN', 'Возврат от клиента'),
  writeOff('WRITE_OFF', 'Брак / списание'),
  adjustment('ADJUSTMENT', 'Инвентаризация');

  const MovementType(this.value, this.label);

  final String value;
  final String label;

  /// Для инвентаризации вводят фактический остаток, а не изменение.
  bool get isAbsolute => this == MovementType.adjustment;
}

@freezed
class EmployeeDto with _$EmployeeDto {
  const factory EmployeeDto({
    required String id,
    required String fullName,
    String? phone,
    String? position,
    OperationRefDto? defaultOperation,
    @Default(false) bool telegramLinked,
    @Default(true) bool isActive,
  }) = _EmployeeDto;

  factory EmployeeDto.fromJson(Map<String, dynamic> json) =>
      _$EmployeeDtoFromJson(json);
}

@freezed
class OperationRefDto with _$OperationRefDto {
  const factory OperationRefDto({
    required String id,
    @Default('') String name,
  }) = _OperationRefDto;

  factory OperationRefDto.fromJson(Map<String, dynamic> json) =>
      _$OperationRefDtoFromJson(json);
}

/// Код привязки Telegram.
///
/// `deepLink` — то, что рабочий открывает; код показываем рядом, потому что
/// ссылку с чужого экрана не нажмёшь, а шесть символов вводятся руками.
@freezed
class TelegramLinkDto with _$TelegramLinkDto {
  const factory TelegramLinkDto({
    required String code,
    required String deepLink,
    required DateTime expiresAt,
  }) = _TelegramLinkDto;

  factory TelegramLinkDto.fromJson(Map<String, dynamic> json) =>
      _$TelegramLinkDtoFromJson(json);
}

@freezed
class OperationDto with _$OperationDto {
  const factory OperationDto({
    required String id,
    required String name,
    String? code,
    @Default(0) int sortOrder,
    @Default(true) bool isActive,
  }) = _OperationDto;

  factory OperationDto.fromJson(Map<String, dynamic> json) =>
      _$OperationDtoFromJson(json);
}

@freezed
class ProductRefDto with _$ProductRefDto {
  const factory ProductRefDto({
    required String id,
    @Default('') String sku,
    @Default('') String name,
  }) = _ProductRefDto;

  factory ProductRefDto.fromJson(Map<String, dynamic> json) =>
      _$ProductRefDtoFromJson(json);
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

/// Сдельная расценка.
///
/// `product` и `employee` пустые — ставка общая: она сработает там, где нет
/// более точной. Это правило живёт на бэкенде (`piece-rates/resolve`), здесь
/// мы его только показываем.
@freezed
class PieceRateDto with _$PieceRateDto {
  const factory PieceRateDto({
    required String id,
    required OperationRefDto operation,
    ProductRefDto? product,
    EmployeeRefDto? employee,
    required String rate,
    DateTime? validFrom,
  }) = _PieceRateDto;

  factory PieceRateDto.fromJson(Map<String, dynamic> json) =>
      _$PieceRateDtoFromJson(json);
}
