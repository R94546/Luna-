import 'dart:ui';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'api_config.dart';
import 'auth_interceptor.dart';

/// HTTP-клиент приложения.
///
/// Язык ответа выбирает сервер по `Accept-Language` — все тексты ошибок
/// уже переведены на бэкенде, и дублировать их словарь в приложении значит
/// однажды разойтись формулировками.
class DioClient {
  DioClient({
    required TokenStore store,
    required Future<void> Function() onSessionExpired,
    required Locale Function() locale,
    String? baseUrl,
  }) {
    final url = baseUrl ?? ApiConfig.baseUrl;

    _dio = Dio(_options(url));

    // Отдельный клиент для обновления токена: он не должен проходить
    // через AuthInterceptor, иначе 401 на самом refresh уйдёт в рекурсию.
    final refreshClient = Dio(_options(url));

    _dio.interceptors.add(
      AuthInterceptor(
        store: store,
        refreshClient: refreshClient,
        onSessionExpired: onSessionExpired,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Accept-Language'] = locale().languageCode;
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;

  Dio get dio => _dio;

  static BaseOptions _options(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    contentType: Headers.jsonContentType,
    // 4xx приходят как DioException и разбираются в ApiException —
    // единая точка обработки вместо проверки кода на каждом вызове.
    validateStatus: (status) => status != null && status < 400,
  );
}
