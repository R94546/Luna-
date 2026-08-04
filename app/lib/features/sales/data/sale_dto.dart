import 'package:freezed_annotation/freezed_annotation.dart';

part 'sale_dto.freezed.dart';
part 'sale_dto.g.dart';

enum PaymentMethod {
  @JsonValue('CASH')
  cash,
  @JsonValue('CARD')
  card,
  @JsonValue('TRANSFER')
  transfer,
  @JsonValue('DEBT')
  debt;

  String get label => switch (this) {
    PaymentMethod.cash => 'Наличные',
    PaymentMethod.card => 'Карта',
    PaymentMethod.transfer => 'Перевод',
    PaymentMethod.debt => 'В долг',
  };

  String get value => switch (this) {
    PaymentMethod.cash => 'CASH',
    PaymentMethod.card => 'CARD',
    PaymentMethod.transfer => 'TRANSFER',
    PaymentMethod.debt => 'DEBT',
  };

  /// В долг денег в кассу не приходит — кассу выбирать не нужно.
  bool get needsCashAccount => this != PaymentMethod.debt;
}

@freezed
class SaleDto with _$SaleDto {
  const factory SaleDto({
    required String id,
    required int saleNumber,
    CustomerRefDto? customer,
    required PaymentMethod paymentMethod,
    required DateTime soldAt,
    @Default('0') String discount,
    required String totalAmount,
    @Default('0') String totalCost,
    @Default('0') String grossProfit,
    @Default('0') String paidAmount,
    @Default('0') String debt,
    @Default(false) bool isCancelled,
    String? cancelReason,
    String? note,
    @Default([]) List<SaleItemDto> items,
  }) = _SaleDto;

  factory SaleDto.fromJson(Map<String, dynamic> json) =>
      _$SaleDtoFromJson(json);
}

@freezed
class CustomerRefDto with _$CustomerRefDto {
  const factory CustomerRefDto({
    required String id,
    @Default('') String name,
    String? phone,
  }) = _CustomerRefDto;

  factory CustomerRefDto.fromJson(Map<String, dynamic> json) =>
      _$CustomerRefDtoFromJson(json);
}

@freezed
class SaleItemDto with _$SaleItemDto {
  const factory SaleItemDto({
    required String id,
    required ProductRefDto product,
    required int quantity,
    required String unitPrice,
    @Default('0') String costPriceSnapshot,
    required String total,
  }) = _SaleItemDto;

  factory SaleItemDto.fromJson(Map<String, dynamic> json) =>
      _$SaleItemDtoFromJson(json);
}

@freezed
class ProductRefDto with _$ProductRefDto {
  const factory ProductRefDto({
    required String id,
    @Default('') String name,
    @Default('') String sku,
  }) = _ProductRefDto;

  factory ProductRefDto.fromJson(Map<String, dynamic> json) =>
      _$ProductRefDtoFromJson(json);
}

/// Итоги списка продаж. Считаются сервером по всей выборке с фильтрами.
@freezed
class SalesSummaryDto with _$SalesSummaryDto {
  const factory SalesSummaryDto({
    @Default('0') String revenue,
    @Default('0') String cost,
    @Default('0') String grossProfit,
    @Default('0') String debt,
  }) = _SalesSummaryDto;

  factory SalesSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$SalesSummaryDtoFromJson(json);
}

@freezed
class SalesPageDto with _$SalesPageDto {
  const factory SalesPageDto({
    @Default([]) List<SaleDto> items,
    @Default(SalesSummaryDto()) SalesSummaryDto summary,
  }) = _SalesPageDto;

  factory SalesPageDto.fromJson(Map<String, dynamic> json) =>
      _$SalesPageDtoFromJson(json);
}
