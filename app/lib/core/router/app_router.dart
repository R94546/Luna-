import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import 'home_shell.dart';

part 'app_router.g.dart';

class Routes {
  const Routes._();

  static const splash = '/';
  static const login = '/login';
  static const home = '/home';
}

/// Роутер с редиректом по состоянию сессии.
///
/// Внутри приложения навигация идёт вкладками HomeShell, а не маршрутами:
/// состав разделов зависит от роли, и описывать его ветками роутера значит
/// пересобирать роутер на каждую смену пользователя.
@riverpod
GoRouter appRouter(Ref ref) {
  final session = ref.watch(sessionControllerProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
    ],
    redirect: (_, state) {
      // Пока сессию проверяем на сервере, держим заставку: увести на экран
      // входа и через миг вернуть обратно — это мигание у каждого вошедшего
      // при каждом запуске.
      if (session.isLoading) {
        return state.matchedLocation == Routes.splash ? null : Routes.splash;
      }

      final user = session.valueOrNull;

      if (user == null) {
        return state.matchedLocation == Routes.login ? null : Routes.login;
      }

      return state.matchedLocation == Routes.home ? null : Routes.home;
    },
  );
}
