import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import 'notification_dto.dart';

class NotificationsApi {
  const NotificationsApi(this._dio);

  final Dio _dio;

  Future<NotificationsPageDto> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/notifications');
      return NotificationsPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post<Map<String, dynamic>>('/notifications/$id/read');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post<Map<String, dynamic>>('/notifications/read-all');
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
