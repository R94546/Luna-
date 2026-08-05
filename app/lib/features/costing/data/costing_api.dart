import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'costing_dto.dart';

class CostingApi {
  const CostingApi(this._dio);

  final Dio _dio;

  // ── Материалы ────────────────────────────────────────────────────────────

  Future<List<MaterialDto>> materials() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/materials',
        queryParameters: {'limit': 100},
      );

      return MaterialsPageDto.fromJson(response.data!).items;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createMaterial({
    required String name,
    required String unit,
    required String unitPrice,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/materials',
        data: {'name': name, 'unit': unit, 'unitPrice': unitPrice},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> updateMaterial(
    String id, {
    String? name,
    String? unit,
    String? unitPrice,
  }) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/materials/$id',
        data: {'name': ?name, 'unit': ?unit, 'unitPrice': ?unitPrice},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> deleteMaterial(String id) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/materials/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  // ── Калькулятор ──────────────────────────────────────────────────────────

  /// Расчёт без сохранения — ответ ничего не создаёт в базе.
  Future<CalculationDto> calculate({
    String? productId,
    required List<CostItemInput> items,
    required String overheadCost,
    required double marginPercent,
    int timeMinutes = 0,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/costing/calculate',
        data: {
          'productId': ?productId,
          'items': items.map((item) => item.toRequest()).toList(),
          'overheadCost': overheadCost,
          'marginPercent': marginPercent,
          'timeMinutes': timeMinutes,
        },
      );

      return CalculationDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<SavedCalculationDto> save({
    required String name,
    String? productId,
    required List<CostItemInput> items,
    required String overheadCost,
    required double marginPercent,
    int timeMinutes = 0,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/costing',
        data: {
          'name': name,
          'productId': ?productId,
          'items': items.map((item) => item.toRequest()).toList(),
          'overheadCost': overheadCost,
          'marginPercent': marginPercent,
          'timeMinutes': timeMinutes,
        },
      );

      return SavedCalculationDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<List<SavedCalculationDto>> saved() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/costing',
        queryParameters: {'limit': 50},
      );

      return SavedCalculationsPageDto.fromJson(response.data!).items;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Записывает себестоимость расчёта в карточку модели.
  Future<void> apply(String id) async {
    try {
      await _dio.post<Map<String, dynamic>>('/costing/$id/apply');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> remove(String id) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/costing/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
