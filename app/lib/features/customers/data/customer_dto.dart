import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer_dto.freezed.dart';
part 'customer_dto.g.dart';

@freezed
class CustomerDto with _$CustomerDto {
  const factory CustomerDto({
    required String id,
    required String name,
    String? phone,
    String? note,
  }) = _CustomerDto;

  factory CustomerDto.fromJson(Map<String, dynamic> json) =>
      _$CustomerDtoFromJson(json);
}

@freezed
class CustomersPageDto with _$CustomersPageDto {
  const factory CustomersPageDto({@Default([]) List<CustomerDto> items}) =
      _CustomersPageDto;

  factory CustomersPageDto.fromJson(Map<String, dynamic> json) =>
      _$CustomersPageDtoFromJson(json);
}

/// Карточка клиента с долгом.
///
/// Долг приходит с сервера посчитанным: он складывается из неоплаченных
/// продаж и предоплат по заказам, и повторный расчёт на клиенте разошёлся
/// бы с тем, что показано в продажах.
@freezed
class CustomerDetailDto with _$CustomerDetailDto {
  const factory CustomerDetailDto({
    required String id,
    required String name,
    String? phone,
    String? note,
    @Default(0) int salesCount,
    @Default('0') String totalAmount,
    @Default('0') String debt,
    @Default(0) int activeOrders,
  }) = _CustomerDetailDto;

  factory CustomerDetailDto.fromJson(Map<String, dynamic> json) =>
      _$CustomerDetailDtoFromJson(json);
}
