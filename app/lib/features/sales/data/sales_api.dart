import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/idempotency.dart';
import 'sale_dto.dart';

/// Позиция продажи в том виде, в каком её собирает экран.
class SaleLine {
  const SaleLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  final ProductDto product;
  final int quantity;
  final String unitPrice;

  Map<String, dynamic> toJson() => {
    'productId': product.id,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };
}

class SalesApi {
  const SalesApi(this._dio);

  final Dio _dio;

  Future<SalesPageDto> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/sales',
        queryParameters: {'limit': 50},
      );

      return SalesPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<ProductDto>> products() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {'limit': 100},
      );

      return (response.data!['items'] as List<dynamic>)
          .map((e) => ProductDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Оформление продажи.
  ///
  /// Одной транзакцией на сервере: остаток списывается, себестоимость
  /// фиксируется снимком, деньги приходуются. Ключ идемпотентности
  /// обязателен — повтор после обрыва связи не должен продать дважды.
  Future<SaleDto> create({
    required List<SaleLine> lines,
    required PaymentMethod paymentMethod,
    required IdempotencyKey key,
    String? cashAccountId,
    String? customerId,
    String discount = '0',
    String? note,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/sales',
        data: {
          'paymentMethod': paymentMethod.value,
          'discount': discount,
          if (paymentMethod.needsCashAccount && cashAccountId != null)
            'cashAccountId': cashAccountId,
          'customerId': ?customerId,
          if (note != null && note.isNotEmpty) 'note': note,
          'items': lines.map((l) => l.toJson()).toList(),
        },
        options: key.options,
      );

      return SaleDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Сторно: товар возвращается на склад, деньги — обратной проводкой.
  /// Продажа остаётся в истории с отметкой.
  Future<void> cancel(String id, String? reason) async {
    try {
      await _dio.delete<void>(
        '/sales/$id',
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
