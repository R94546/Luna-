import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/api/api_exception.dart';

DioException _error({
  int? status,
  Object? data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/sales');

  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: data,
          ),
  );
}

void main() {
  /// Бэкенд уже перевёл сообщение по Accept-Language и знает причину
  /// точнее, чем клиент может угадать по коду. Задача разбора — донести
  /// его до экрана, ничего не потеряв.
  test('берёт код и сообщение из ответа', () {
    final exception = ApiException.from(
      _error(
        status: 422,
        data: {
          'code': 'INSUFFICIENT_STOCK',
          'message': 'Omborda atigi 5 juft bor',
          'details': {'available': 5, 'requested': 8},
        },
      ),
    );

    expect(exception.statusCode, 422);
    expect(exception.code, 'INSUFFICIENT_STOCK');
    expect(exception.message, 'Omborda atigi 5 juft bor');
    expect(exception.details['available'], 5);
  });

  test('разбирает ошибки по полям формы', () {
    final exception = ApiException.from(
      _error(
        status: 400,
        data: {
          'code': 'VALIDATION_ERROR',
          'message': 'Проверьте поля',
          'details': {
            'fields': {
              'amount': 'Значение должно быть больше нуля',
              'cashAccountId': 'Выберите кассу',
            },
          },
        },
      ),
    );

    expect(exception.fieldErrors, {
      'amount': 'Значение должно быть больше нуля',
      'cashAccountId': 'Выберите кассу',
    });
  });

  test('401 распознаётся как проблема авторизации', () {
    final exception = ApiException.from(
      _error(status: 401, data: {'code': 'UNAUTHORIZED', 'message': 'Kirish'}),
    );

    expect(exception.isUnauthorized, isTrue);
  });

  /// До сервера не дошли — человеку нужно понять, что дело в связи,
  /// а не в его данных. «Ошибка 0» этого не сообщает.
  test('отсутствие ответа — это проблема сети', () {
    final exception = ApiException.from(
      _error(type: DioExceptionType.connectionError),
    );

    expect(exception.isNetwork, isTrue);
    expect(exception.message, contains('связи'));
  });

  test('таймаут тоже считается проблемой сети', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      expect(ApiException.from(_error(type: type)).isNetwork, isTrue);
    }
  });

  test('не падает на теле неожиданного вида', () {
    final exception = ApiException.from(_error(status: 502, data: '<html>'));

    expect(exception.statusCode, 502);
    expect(exception.code, 'UNKNOWN');
    expect(exception.message, contains('502'));
  });

  test('переваривает ответ без деталей', () {
    final exception = ApiException.from(
      _error(status: 404, data: {'code': 'NOT_FOUND', 'message': 'Topilmadi'}),
    );

    expect(exception.fieldErrors, isEmpty);
    expect(exception.details, isEmpty);
  });
}
