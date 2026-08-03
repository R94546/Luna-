import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/auth_interceptor.dart';
import 'auth_dto.dart';

/// Только HTTP: ни состояния, ни хранения токенов.
class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthResponse> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'phone': phone, 'password': password},
        // Токена ещё нет — незачем пытаться его подставить и обновлять.
        options: AuthInterceptor.skipAuth,
      );

      return AuthResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Кто я. Вызывается при старте по сохранённому токену: он мог быть
  /// отозван с другого устройства, и узнать это надо до показа экрана.
  Future<MeResponse> me() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      return MeResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
    } on DioException {
      // Выход не должен падать: даже если сервер недоступен, локально
      // токены надо стереть, иначе человек останется «внутри».
    }
  }
}
