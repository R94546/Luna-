import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'catalog_dto.dart';

/// Справочники: товары, склад, сотрудники, операции, расценки.
///
/// Один клиент на четыре раздела, а не четыре файла: запросы здесь —
/// это CRUD без своей логики, и разносить их значит четыре раза повторить
/// один и тот же `try/catch`.
class CatalogApi {
  const CatalogApi(this._dio);

  final Dio _dio;

  // ── Товары ───────────────────────────────────────────────────────────────

  Future<List<ProductDto>> products({bool includeArchived = false}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {
          'limit': 100,
          if (!includeArchived) 'isActive': 'true',
        },
      );

      return ProductsPageDto.fromJson(response.data!).items;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createProduct({
    required String sku,
    required String name,
    required String salePrice,
    required String costPrice,
    required int minStockLevel,
    required int initialStock,
    String? category,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/products',
        data: {
          'sku': sku,
          'name': name,
          'salePrice': salePrice,
          'costPrice': costPrice,
          'minStockLevel': minStockLevel,
          'initialStock': initialStock,
          if (category != null && category.isNotEmpty) 'category': category,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> updateProduct(
    String id, {
    String? sku,
    String? name,
    String? category,
    String? salePrice,
    String? costPrice,
    int? minStockLevel,
    bool? isActive,
  }) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/products/$id',
        data: {
          'sku': ?sku,
          'name': ?name,
          'category': ?category,
          'salePrice': ?salePrice,
          'costPrice': ?costPrice,
          'minStockLevel': ?minStockLevel,
          'isActive': ?isActive,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> archiveProduct(String id) async {
    try {
      await _dio.delete<void>('/products/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Ручное движение склада: приход, списание или инвентаризация.
  Future<void> createMovement({
    required String productId,
    required MovementType type,
    required int quantity,
    String? note,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/stock/movements',
        data: {
          'productId': productId,
          'type': type.value,
          'quantity': quantity,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  // ── Сотрудники ───────────────────────────────────────────────────────────

  Future<List<EmployeeDto>> employees({bool includeFired = false}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/employees',
        queryParameters: {if (!includeFired) 'isActive': 'true'},
      );

      return (response.data ?? [])
          .map((e) => EmployeeDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createEmployee({
    required String fullName,
    String? phone,
    String? position,
    String? defaultOperationId,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/employees',
        data: {
          'fullName': fullName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (position != null && position.isNotEmpty) 'position': position,
          'defaultOperationId': ?defaultOperationId,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> updateEmployee(
    String id, {
    String? fullName,
    String? phone,
    String? position,
    String? defaultOperationId,
    bool? isActive,
  }) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/employees/$id',
        data: {
          'fullName': ?fullName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'position': ?position,
          'defaultOperationId': ?defaultOperationId,
          'isActive': ?isActive,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> fireEmployee(String id) async {
    try {
      await _dio.delete<void>('/employees/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<TelegramLinkDto> createTelegramLink(String employeeId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/employees/$employeeId/telegram-link',
      );

      return TelegramLinkDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> unlinkTelegram(String employeeId) async {
    try {
      await _dio.delete<void>('/employees/$employeeId/telegram-link');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  // ── Операции ─────────────────────────────────────────────────────────────

  Future<List<OperationDto>> operations({bool includeInactive = false}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/operations',
        queryParameters: {if (includeInactive) 'includeInactive': 'true'},
      );

      return (response.data ?? [])
          .map((e) => OperationDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createOperation({
    required String name,
    String? code,
    int sortOrder = 0,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/operations',
        data: {
          'name': name,
          if (code != null && code.isNotEmpty) 'code': code,
          'sortOrder': sortOrder,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> updateOperation(
    String id, {
    String? name,
    String? code,
    int? sortOrder,
    bool? isActive,
  }) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/operations/$id',
        data: {
          'name': ?name,
          'code': ?code,
          'sortOrder': ?sortOrder,
          'isActive': ?isActive,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> archiveOperation(String id) async {
    try {
      await _dio.delete<void>('/operations/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  // ── Расценки ─────────────────────────────────────────────────────────────

  Future<List<PieceRateDto>> pieceRates() async {
    try {
      final response = await _dio.get<List<dynamic>>('/piece-rates');

      return (response.data ?? [])
          .map((e) => PieceRateDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createPieceRate({
    required String operationId,
    required String rate,
    String? productId,
    String? employeeId,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/piece-rates',
        data: {
          'operationId': operationId,
          'rate': rate,
          'productId': ?productId,
          'employeeId': ?employeeId,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> deletePieceRate(String id) async {
    try {
      await _dio.delete<void>('/piece-rates/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
