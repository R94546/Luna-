import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Пара токенов.
class Tokens {
  const Tokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

/// Хранилище токенов.
///
/// `flutter_secure_storage`, а не `SharedPreferences`: на Android последний —
/// обычный XML в песочнице приложения, доступный из бэкапа и на устройстве
/// с root. Refresh-токен живёт 30 дней, и его утечка означает вход в кассу
/// цеха.
///
/// Интерфейс отдельно от реализации: тесты интерцептора не должны тянуть
/// за собой платформенный канал.
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> save(Tokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'luna.access_token';
  static const _refreshKey = 'luna.refresh_token';

  @override
  Future<Tokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);

    if (access == null || refresh == null) return null;
    return Tokens(access: access, refresh: refresh);
  }

  @override
  Future<void> save(Tokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.access);
    await _storage.write(key: _refreshKey, value: tokens.refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// Хранилище в памяти — для тестов и для web, где безопасного места всё
/// равно нет, а web у нас только инструмент разработки.
class InMemoryTokenStore implements TokenStore {
  Tokens? _tokens;

  @override
  Future<Tokens?> read() async => _tokens;

  @override
  Future<void> save(Tokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
