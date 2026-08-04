import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/notification_dto.dart';
import '../../data/notifications_api.dart';

part 'notifications_provider.g.dart';

@riverpod
NotificationsApi notificationsApi(Ref ref) =>
    NotificationsApi(ref.watch(dioProvider));

/// Лента уведомлений.
///
/// keepAlive — счётчик непрочитанных живёт в нижней навигации и не должен
/// пропадать при переключении вкладок. Сторож на сервере ходит раз в час,
/// поэтому опроса по таймеру здесь нет: список обновляется при открытии
/// экрана и жестом «потянуть».
@Riverpod(keepAlive: true)
class Notifications extends _$Notifications {
  @override
  Future<NotificationsPageDto> build() =>
      ref.watch(notificationsApiProvider).list();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(notificationsApiProvider).list(),
    );
  }

  Future<void> markRead(String id) async {
    await ref.read(notificationsApiProvider).markRead(id);
    await refresh();
  }

  Future<void> markAllRead() async {
    await ref.read(notificationsApiProvider).markAllRead();
    await refresh();
  }
}

/// Число непрочитанных для значка. Пока лента грузится — ноль, чтобы
/// на кнопке не мигал бейдж при каждом обновлении.
@riverpod
int unreadCount(Ref ref) => ref.watch(notificationsProvider).value?.unread ?? 0;
