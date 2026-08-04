import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'customer_dto.dart';

class CustomersApi {
  const CustomersApi(this._dio);

  final Dio _dio;

  Future<List<CustomerDto>> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/customers',
        queryParameters: {'limit': 100},
      );

      return CustomersPageDto.fromJson(response.data!).items;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<CustomerDetailDto> detail(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/customers/$id');
      return CustomerDetailDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> create({
    required String name,
    String? phone,
    String? note,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/customers',
        data: {
          'name': name,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> update(
    String id, {
    String? name,
    String? phone,
    String? note,
  }) async {
    try {
      await _dio.patch<Map<String, dynamic>>(
        '/customers/$id',
        data: {
          'name': ?name,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'note': ?note,
        },
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> archive(String id) async {
    try {
      await _dio.delete<void>('/customers/$id');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
