import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/api/api_config.dart';

void main() {
  group('ApiConfig.resolve', () {
    /// С эмулятора `localhost` — это сам эмулятор, а не машина
    /// разработчика: приложение молча не достучалось бы до бэкенда.
    test('на Android-эмуляторе адрес шлюза, а не localhost', () {
      final url = ApiConfig.resolve(
        override: '',
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(url, 'http://10.0.2.2:3000/api/v1');
    });

    test('на web — localhost', () {
      final url = ApiConfig.resolve(
        override: '',
        isWeb: true,
        platform: TargetPlatform.android,
      );

      expect(url, 'http://localhost:3000/api/v1');
    });

    test('на десктопе — localhost', () {
      final url = ApiConfig.resolve(
        override: '',
        isWeb: false,
        platform: TargetPlatform.windows,
      );

      expect(url, 'http://localhost:3000/api/v1');
    });

    /// Физическое устройство ходит по адресу машины в локальной сети —
    /// угадать его нельзя, поэтому он передаётся через --dart-define.
    test('переданный адрес перебивает любой дефолт', () {
      const custom = 'http://192.168.1.5:3000/api/v1';

      for (final isWeb in [true, false]) {
        for (final platform in [
          TargetPlatform.android,
          TargetPlatform.windows,
        ]) {
          expect(
            ApiConfig.resolve(
              override: custom,
              isWeb: isWeb,
              platform: platform,
            ),
            custom,
          );
        }
      }
    });

    test('пустое значение не считается переопределением', () {
      final url = ApiConfig.resolve(
        override: '',
        isWeb: false,
        platform: TargetPlatform.android,
      );

      expect(url, isNot(''));
    });
  });
}
