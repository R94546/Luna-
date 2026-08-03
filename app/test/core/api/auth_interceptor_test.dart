import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_app/core/api/auth_interceptor.dart';
import 'package:luna_app/core/storage/token_store.dart';

/// Управляемый сервер: считает запросы и отдаёт заготовленные ответы.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.refreshDelay = Duration.zero});

  final Duration refreshDelay;

  int refreshCalls = 0;
  final List<String> protectedAuthHeaders = [];

  /// Токен, который сервер считает действующим.
  String validAccess = 'access-2';

  /// Что вернёт `/auth/refresh`. По умолчанию — действующий токен;
  /// расхождение с `validAccess` изображает сервер, выдавший токен,
  /// который сам же не принимает.
  String? issuedAccess;

  /// Refresh отозван или истёк — обновиться уже нельзя.
  bool refreshFails = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      refreshCalls++;
      if (refreshDelay > Duration.zero) {
        await Future<void>.delayed(refreshDelay);
      }

      if (refreshFails) {
        return ResponseBody.fromString(
          '{"code":"INVALID_REFRESH_TOKEN","message":"Sessiya yaroqsiz"}',
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      return ResponseBody.fromString(
        '{"accessToken":"${issuedAccess ?? validAccess}",'
        '"refreshToken":"refresh-2"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final auth = options.headers['Authorization'] as String?;
    protectedAuthHeaders.add(auth ?? '');

    // Старый токен отвергается, свежий принимается — как на настоящем сервере.
    if (auth == 'Bearer $validAccess') {
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '{"code":"UNAUTHORIZED","message":"Avtorizatsiya talab qilinadi"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeAdapter adapter;
  late TokenStore store;
  late Dio dio;
  late int expiredCalls;

  Future<void> setUpClient({Duration refreshDelay = Duration.zero}) async {
    adapter = _FakeAdapter(refreshDelay: refreshDelay);
    store = InMemoryTokenStore();
    expiredCalls = 0;

    await store.save(const Tokens(access: 'access-1', refresh: 'refresh-1'));

    final refreshClient = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    dio =
        Dio(
            BaseOptions(
              baseUrl: 'http://test',
              validateStatus: (status) => status != null && status < 400,
            ),
          )
          ..httpClientAdapter = adapter
          ..interceptors.add(
            AuthInterceptor(
              store: store,
              refreshClient: refreshClient,
              onSessionExpired: () async => expiredCalls++,
            ),
          );
  }

  test('подставляет access-токен в заголовок', () async {
    await setUpClient();
    adapter.validAccess = 'access-1';

    await dio.get<dynamic>('/orders');

    expect(adapter.protectedAuthHeaders.first, 'Bearer access-1');
  });

  test('на 401 обновляет токен и повторяет запрос', () async {
    await setUpClient();

    final response = await dio.get<dynamic>('/orders');

    expect(response.statusCode, 200);
    expect(adapter.refreshCalls, 1);
    // Первый заход со старым токеном, повтор — с новым.
    expect(adapter.protectedAuthHeaders, [
      'Bearer access-1',
      'Bearer access-2',
    ]);
  });

  test('сохраняет новую пару токенов', () async {
    await setUpClient();

    await dio.get<dynamic>('/orders');
    final tokens = await store.read();

    expect(tokens?.access, 'access-2');
    expect(tokens?.refresh, 'refresh-2');
  });

  /// Главный тест этого слоя.
  ///
  /// Бэкенд ротирует refresh и считает повторное использование отозванного
  /// признаком кражи: отзывается вся семья токенов, человека выкидывает
  /// со всех устройств. Два параллельных 401 не должны породить два
  /// `/auth/refresh` — иначе пользователь разлогинится, не сделав ничего.
  test('два одновременных 401 дают ровно одно обновление', () async {
    await setUpClient(refreshDelay: const Duration(milliseconds: 50));

    final responses = await Future.wait([
      dio.get<dynamic>('/orders'),
      dio.get<dynamic>('/sales'),
      dio.get<dynamic>('/cash/accounts'),
    ]);

    expect(adapter.refreshCalls, 1);
    expect(responses.every((r) => r.statusCode == 200), isTrue);
  });

  /// Refresh отозван — обновиться нельзя, и приложение обязано узнать об
  /// этом, чтобы увести человека на экран входа, а не крутить спиннер.
  test('отозванный refresh завершает сессию', () async {
    await setUpClient();
    adapter.refreshFails = true;

    await expectLater(
      dio.get<dynamic>('/orders'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.refreshCalls, 1);
    expect(expiredCalls, 1);
    expect(await store.read(), isNull, reason: 'токены должны быть стёрты');
  });

  /// Второй 401 подряд означает, что дело не в токене: повторять бесконечно
  /// нельзя, иначе один сломанный эндпоинт зациклит приложение.
  test('запрос повторяется только один раз', () async {
    await setUpClient();
    // Сервер выдаёт токен, который сам же не принимает.
    adapter.issuedAccess = 'не-принимается';

    await expectLater(
      dio.get<dynamic>('/orders'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.refreshCalls, 1);
  });

  test('без токенов в хранилище обновление не запускается', () async {
    await setUpClient();
    await store.clear();

    await expectLater(
      dio.get<dynamic>('/orders'),
      throwsA(isA<DioException>()),
    );

    expect(adapter.refreshCalls, 0);
    expect(expiredCalls, 1);
  });
}
