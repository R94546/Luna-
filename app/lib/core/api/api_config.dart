import 'package:flutter/foundation.dart';

/// Адрес API.
///
/// Захардкодить его нельзя: с эмулятора `localhost` — это сам эмулятор,
/// а не машина разработчика, и приложение молча не достучится до бэкенда.
/// Поэтому дефолт зависит от платформы, а для физического устройства
/// адрес передаётся снаружи:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.5:3000/api/v1
/// ```
class ApiConfig {
  const ApiConfig._();

  static const _override = String.fromEnvironment('API_BASE_URL');

  /// Android-эмулятор видит хост-машину по 10.0.2.2 — это его шлюз,
  /// а не адрес самого устройства.
  static const _androidEmulator = 'http://10.0.2.2:3000/api/v1';
  static const _localhost = 'http://localhost:3000/api/v1';

  static String get baseUrl => resolve(
    override: _override,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// Вынесено из геттера ради тестов: подменять `kIsWeb` и
  /// `defaultTargetPlatform` в тестах дороже, чем передать параметрами.
  @visibleForTesting
  static String resolve({
    required String override,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (override.isNotEmpty) return override;
    if (isWeb) return _localhost;

    return platform == TargetPlatform.android ? _androidEmulator : _localhost;
  }

  static const connectTimeout = Duration(seconds: 10);

  /// Дашборд собирает семь агрегатов сразу — на слабом соединении
  /// пять секунд ему может не хватить.
  static const receiveTimeout = Duration(seconds: 20);
}
