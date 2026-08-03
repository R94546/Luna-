import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../widgets/placeholder_screen.dart';

part 'app_router.g.dart';

class Routes {
  const Routes._();

  static const splash = '/';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const soon = '/soon';
}

/// Роутер с редиректом по состоянию сессии и роли.
///
/// Роль важна не меньше факта входа: дашборд на бэкенде помечен
/// `@Roles(UserRole.OWNER)`, и отправить туда мастера значит показать ему
/// 403 сразу после успешного логина.
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
      GoRoute(
        path: Routes.dashboard,
        builder: (_, _) => const DashboardScreen(),
      ),
      GoRoute(path: Routes.soon, builder: (_, _) => const PlaceholderScreen()),
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

      final home = user.role.canSeeDashboard ? Routes.dashboard : Routes.soon;

      // С заставки и экрана входа вошедшего уводим на его домашний экран.
      if (state.matchedLocation == Routes.splash ||
          state.matchedLocation == Routes.login) {
        return home;
      }

      // Мастер или бухгалтер, попавший на дашборд, получил бы 403 —
      // возвращаем на доступный ему экран.
      if (state.matchedLocation == Routes.dashboard &&
          !user.role.canSeeDashboard) {
        return Routes.soon;
      }

      return null;
    },
  );
}
