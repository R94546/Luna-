import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';

/// Подстановка access-токена и обновление пары при 401.
///
/// Главное здесь — обновление идёт СТРОГО ПО ОДНОМУ за раз.
///
/// Бэкенд ротирует refresh-токен и считает повторное использование
/// отозванного признаком кражи: отзывается вся семья токенов, и человека
/// выкидывает со всех устройств. Если два параллельных запроса упрутся
/// в 401 одновременно, наивный интерцептор пошлёт два `/auth/refresh`
/// с одним и тем же токеном — второй будет расценен как кража, и
/// пользователь разлогинится на ровном месте, не сделав ничего плохого.
///
/// Поэтому первый 401 запускает обновление, а остальные ждут тот же
/// `Future` и повторяют свой запрос уже с новым токеном.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore store,
    required Dio refreshClient,
    required Future<void> Function() onSessionExpired,
  }) : _store = store,
       _refreshClient = refreshClient,
       _onSessionExpired = onSessionExpired;

  final TokenStore _store;

  /// Отдельный Dio без этого интерцептора: обновление токена не должно
  /// само попасть в перехват 401 и уйти в бесконечную рекурсию.
  final Dio _refreshClient;

  final Future<void> Function() _onSessionExpired;

  /// Идущее обновление. Пока не null — все остальные 401 ждут его.
  Future<Tokens?>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuth] != true) {
      final tokens = await _store.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.access}';
      }
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isAuthFailure = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[_retried] == true;

    // Повторяем ровно один раз: если запрос упал с 401 и после свежего
    // токена, дело не в токене, и второй заход ничего не изменит.
    if (!isAuthFailure || alreadyRetried) {
      return handler.next(err);
    }

    final tokens = await _refreshOnce();

    if (tokens == null) {
      await _onSessionExpired();
      return handler.next(err);
    }

    try {
      final options = err.requestOptions
        ..headers['Authorization'] = 'Bearer ${tokens.access}'
        ..extra[_retried] = true;

      final response = await _refreshClient.fetch<dynamic>(options);
      return handler.resolve(response);
    } on DioException catch (error) {
      return handler.next(error);
    }
  }

  /// Обновление, разделяемое всеми ждущими запросами.
  Future<Tokens?> _refreshOnce() {
    // Обновление уже идёт — присоединяемся к нему вместо второго запроса.
    final running = _refreshing;
    if (running != null) return running;

    final future = _performRefresh();
    _refreshing = future;

    return future.whenComplete(() => _refreshing = null);
  }

  Future<Tokens?> _performRefresh() async {
    final current = await _store.read();
    if (current == null) return null;

    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': current.refresh},
        options: Options(extra: {_skipAuth: true}),
      );

      final data = response.data;
      if (data == null) return null;

      final tokens = Tokens(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
      );

      await _store.save(tokens);
      return tokens;
    } on DioException {
      // Refresh мёртв: истёк или отозван. Сессии больше нет.
      await _store.clear();
      return null;
    }
  }

  /// Пометка «этому запросу токен не нужен» — для login и refresh.
  static const _skipAuth = 'luna.skipAuth';

  /// Пометка «этот запрос уже повторяли после обновления».
  static const _retried = 'luna.retried';

  static Options get skipAuth => Options(extra: {_skipAuth: true});
}
