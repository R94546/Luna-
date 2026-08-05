import 'package:dio/dio.dart';

import '../l10n/fallback_texts.dart';

/// Ошибка от API в том виде, в каком её можно показать пользователю.
///
/// Бэкенд отдаёт единый формат и уже локализованное сообщение по заголовку
/// `Accept-Language`. Клиент его показывает, а не сочиняет своё: иначе одна
/// и та же ошибка будет звучать по-разному в приложении и в боте.
///
/// ```json
/// { "statusCode": 422, "code": "INSUFFICIENT_STOCK",
///   "message": "Omborda atigi 5 juft bor",
///   "details": { "available": 5, "requested": 8 } }
/// ```
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.details = const {},
  });

  final int statusCode;
  final String code;
  final String message;

  /// Ошибки по полям формы: `{ "amount": "Значение должно быть больше нуля" }`.
  final Map<String, String> fieldErrors;
  final Map<String, dynamic> details;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetwork => code == _networkCode;

  static const _networkCode = 'NETWORK_ERROR';

  factory ApiException.from(DioException error) {
    final response = error.response;

    // Ответа нет — до сервера не дошли. Показывать «ошибка 0» бессмысленно,
    // человеку нужно понять, что дело в связи, а не в его данных.
    if (response == null || _isConnectionProblem(error.type)) {
      return ApiException(
        statusCode: 0,
        code: _networkCode,
        message: FallbackTexts.network,
      );
    }

    final data = response.data;

    if (data is! Map<String, dynamic>) {
      return ApiException(
        statusCode: response.statusCode ?? 0,
        code: 'UNKNOWN',
        message: FallbackTexts.serverWithCode(response.statusCode ?? 0),
      );
    }

    return ApiException(
      statusCode: response.statusCode ?? 0,
      code: data['code'] as String? ?? 'UNKNOWN',
      message: data['message'] as String? ?? FallbackTexts.server,
      fieldErrors: _fieldErrors(data['details']),
      details: _details(data['details']),
    );
  }

  static bool _isConnectionProblem(DioExceptionType type) =>
      type == DioExceptionType.connectionError ||
      type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.receiveTimeout ||
      type == DioExceptionType.sendTimeout;

  static Map<String, String> _fieldErrors(Object? details) {
    if (details is! Map) return const {};

    final fields = details['fields'];
    if (fields is! Map) return const {};

    return fields.map((key, value) => MapEntry('$key', '$value'));
  }

  static Map<String, dynamic> _details(Object? details) {
    if (details is! Map) return const {};
    return Map<String, dynamic>.from(details);
  }

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
