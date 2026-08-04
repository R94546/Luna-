import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/notification_dto.dart';
import 'providers/notifications_provider.dart';

/// Лента уведомлений: что случилось в цехе, пока никто не смотрел.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = notifications.value?.unread ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Прочитать все'),
            ),
        ],
      ),
      body: AsyncValueBuilder(
        value: notifications,
        onRetry: () => ref.read(notificationsProvider.notifier).refresh(),
        builder: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'Пока тихо',
              message:
                  'Здесь появятся заканчивающийся товар '
                  'и заказы с вышедшим сроком',
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) => _NotificationTile(
                notification: page.items[index],
                onTap: () => ref
                    .read(notificationsProvider.notifier)
                    .markRead(page.items[index].id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationDto notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.isRead;

    return ListTile(
      onTap: unread ? onTap : null,
      leading: Icon(
        notification.icon,
        color: unread ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        notification.title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(notification.body),
      trailing: Text(
        _ago(notification.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      isThreeLine: notification.body.length > 40,
    );
  }

  /// «12 мин», «3 ч», «04.08». Точное время в уведомлении не нужно —
  /// важно, свежее оно или висит со вчера.
  static String _ago(DateTime moment) {
    final difference = DateTime.now().difference(moment);

    if (difference.inMinutes < 1) return 'только что';
    if (difference.inHours < 1) return '${difference.inMinutes} мин';
    if (difference.inDays < 1) return '${difference.inHours} ч';

    return '${moment.day.toString().padLeft(2, '0')}.'
        '${moment.month.toString().padLeft(2, '0')}';
  }
}
