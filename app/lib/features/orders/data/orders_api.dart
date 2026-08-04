import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../sales/data/sale_dto.dart';
import 'order_dto.dart';

class OrdersApi {
  const OrdersApi(this._dio);

  final Dio _dio;

  Future<OrdersPageDto> list({
    OrderStatus? status,
    bool overdue = false,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/orders',
        queryParameters: {
          'limit': 50,
          'status': ?status?.value,
          if (overdue) 'overdue': true,
        },
      );

      return OrdersPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<OrderDto> byId(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/orders/$id');
      return OrderDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Смена статуса.
  ///
  /// Переход в ISSUED — единственный с последствиями за пределами заказа:
  /// товар уходит со склада, и, если попросили, оформляется продажа.
  /// Сервер делает это одной транзакцией.
  Future<OrderDto> changeStatus(
    String id, {
    required OrderStatus status,
    bool createSale = false,
    String? cashAccountId,
    String? paidAmount,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/orders/$id/status',
        data: {
          'status': status.value,
          'createSale': createSale,
          'paymentMethod': paymentMethod.value,
          'cashAccountId': ?cashAccountId,
          'paidAmount': ?paidAmount,
        },
      );

      return OrderDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Отметка о произведённом.
  ///
  /// Ставится вручную: у выработки в схеме нет ссылки на заказ, и связать
  /// «сшили 18 пар Спорт-12» с конкретным заказом, когда их два на одну
  /// модель, не по чему.
  Future<OrderDto> updateProgress(
    String id,
    Map<String, int> producedByItem,
  ) async {
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/orders/$id/progress',
        data: {
          'items': [
            for (final entry in producedByItem.entries)
              {'itemId': entry.key, 'producedQuantity': entry.value},
          ],
        },
      );

      return OrderDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
