import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../l10n/app_localizations.dart';

part 'order_dto.freezed.dart';
part 'order_dto.g.dart';

/// Статус заказа.
///
/// Переходы решает сервер и присылает их в `availableTransitions` — здесь
/// только названия и вид. Продублировать автомат в клиенте значит завести
/// второй источник правды, который однажды разойдётся с первым.
enum OrderStatus {
  @JsonValue('NEW')
  isNew,
  @JsonValue('IN_PROGRESS')
  inProgress,
  @JsonValue('READY')
  ready,
  @JsonValue('ISSUED')
  issued,
  @JsonValue('CANCELLED')
  cancelled;

  String label(L l10n) => switch (this) {
    OrderStatus.isNew => l10n.ordersStatusNew,
    OrderStatus.inProgress => l10n.ordersStatusInProgress,
    OrderStatus.ready => l10n.ordersStatusReady,
    OrderStatus.issued => l10n.ordersStatusIssued,
    OrderStatus.cancelled => l10n.ordersStatusCancelled,
  };

  String get value => switch (this) {
    OrderStatus.isNew => 'NEW',
    OrderStatus.inProgress => 'IN_PROGRESS',
    OrderStatus.ready => 'READY',
    OrderStatus.issued => 'ISSUED',
    OrderStatus.cancelled => 'CANCELLED',
  };
}

@freezed
class OrderDto with _$OrderDto {
  const factory OrderDto({
    required String id,
    required int orderNumber,
    required OrderStatus status,
    @Default([]) List<OrderStatus> availableTransitions,
    CustomerRefDto? customer,
    String? dueDate,
    @Default(false) bool isOverdue,
    required String totalAmount,
    @Default('0') String prepaidAmount,
    @Default('0') String debt,
    required ProgressDto progress,
    String? note,
    DateTime? issuedAt,
    @Default([]) List<OrderItemDto> items,
  }) = _OrderDto;

  factory OrderDto.fromJson(Map<String, dynamic> json) =>
      _$OrderDtoFromJson(json);
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

/// Готовность заказа. Считает сервер: дублировать формулу во Flutter —
/// гарантия расхождения цифр между экранами.
@freezed
class ProgressDto with _$ProgressDto {
  const factory ProgressDto({
    @Default(0) int ordered,
    @Default(0) int produced,
    @Default(0) int percent,
  }) = _ProgressDto;

  factory ProgressDto.fromJson(Map<String, dynamic> json) =>
      _$ProgressDtoFromJson(json);
}

@freezed
class OrderItemDto with _$OrderItemDto {
  const factory OrderItemDto({
    required String id,
    required ProductRefDto product,
    required int quantity,
    @Default(0) int producedQuantity,
    required String unitPrice,
    required String total,
  }) = _OrderItemDto;

  factory OrderItemDto.fromJson(Map<String, dynamic> json) =>
      _$OrderItemDtoFromJson(json);
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

@freezed
class OrdersPageDto with _$OrdersPageDto {
  const factory OrdersPageDto({@Default([]) List<OrderDto> items}) =
      _OrdersPageDto;

  factory OrdersPageDto.fromJson(Map<String, dynamic> json) =>
      _$OrdersPageDtoFromJson(json);
}
