import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/presentation/providers/notifications_provider.dart';
import '../../reports/presentation/reports_screen.dart';
import 'widgets/change_password_dialog.dart';

/// Настройки: кто вошёл, смена пароля, выход.
///
/// Отдельного экрана профиля нет намеренно — имя и телефон меняет
/// владелец через сотрудников, а здесь человеку нужно понять, под кем
/// он сидит, и выйти.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final unread = ref.watch(unreadCountProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session?.fullName ?? '—',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      session?.role.label,
                      session?.phone,
                    ].whereType<String>().join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (session?.companyName != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          session!.companyName!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Уведомления'),
                  subtitle: const Text('Остатки и просроченные заказы'),
                  trailing: unread > 0
                      ? Badge(label: Text('$unread'))
                      : const Icon(Icons.chevron_right),
                  onTap: () => _open(context, const NotificationsScreen()),
                ),
                // Отчёты — там же, где деньги: бэкенд отдаёт их владельцу
                // и бухгалтеру, мастеру эта кнопка ответила бы 403.
                if (session?.role.canSeeMoney ?? false) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Отчёты'),
                    subtitle: const Text('Выгрузка в Excel и PDF'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, const ReportsScreen()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Сменить пароль'),
                  onTap: () => _changePassword(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Сервер'),
                  subtitle: Text(ApiConfig.baseUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Выйти',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => _logout(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );

    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Пароль изменён')));
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выйти?'),
        content: const Text('Придётся войти заново по телефону и паролю.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Роутер уведёт на вход сам, как только сессия станет null.
    await ref.read(sessionControllerProvider.notifier).logout();
  }
}
