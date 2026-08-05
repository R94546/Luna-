import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/api/dio_client.dart';
import '../../../../core/l10n/locale_controller.dart';
import '../../../../core/storage/token_store.dart';
import '../../data/auth_api.dart';
import '../../domain/session.dart';

part 'session_provider.g.dart';

/// Хранилище токенов.
///
/// На web безопасного места всё равно нет, а web у нас только инструмент
/// разработки — там держим в памяти, чтобы не тянуть платформенный канал,
/// которого в браузере не существует.
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) =>
    kIsWeb ? InMemoryTokenStore() : SecureTokenStore();

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final client = DioClient(
    store: ref.watch(tokenStoreProvider),
    // Сессия протухла — сбрасываем состояние, роутер сам уведёт на вход.
    onSessionExpired: () async =>
        ref.read(sessionControllerProvider.notifier).forceLogout(),
    // Язык запроса — тот, на котором человек читает экран, а не тот, что
    // стоит в прошивке: иначе экран узбекский, а ошибка из-под него
    // приходит по-русски. Читается на каждом запросе, чтобы переключение
    // языка действовало сразу.
    locale: () => resolveLocale(ref.read(localeControllerProvider)),
  );

  return client.dio;
}

@Riverpod(keepAlive: true)
AuthApi authApi(Ref ref) => AuthApi(ref.watch(dioProvider));

/// Текущая сессия.
///
/// `null` внутри `AsyncData` означает «точно не вошли», в отличие от
/// `AsyncLoading` — «ещё выясняем». Роутер обязан различать эти два
/// состояния, иначе при старте мигнёт экраном входа у вошедшего человека.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  @override
  Future<Session?> build() async {
    final tokens = await ref.watch(tokenStoreProvider).read();
    if (tokens == null) return null;

    try {
      // Токен мог быть отозван с другого устройства — проверяем на сервере,
      // а не верим его наличию в хранилище.
      final me = await ref.read(authApiProvider).me();
      return Session.fromDto(me.user, me.company);
    } on Object {
      await ref.read(tokenStoreProvider).clear();
      return null;
    }
  }

  Future<void> login({required String phone, required String password}) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final response = await ref
          .read(authApiProvider)
          .login(phone: phone, password: password);

      await ref
          .read(tokenStoreProvider)
          .save(
            Tokens(
              access: response.accessToken,
              refresh: response.refreshToken,
            ),
          );

      return Session.fromDto(response.user, response.company);
    });
  }

  Future<void> logout() async {
    final store = ref.read(tokenStoreProvider);
    final tokens = await store.read();

    if (tokens != null) {
      await ref.read(authApiProvider).logout(tokens.refresh);
    }

    await store.clear();
    state = const AsyncData(null);
  }

  /// Выход не по воле пользователя: refresh отозван или истёк.
  Future<void> forceLogout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }
}
