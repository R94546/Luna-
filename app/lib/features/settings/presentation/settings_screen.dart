import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/l10n/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
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
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
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
                      session?.role.label(l),
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
                  title: Text(l.settingsNotifications),
                  subtitle: Text(l.settingsNotificationsHint),
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
                    title: Text(l.settingsReports),
                    subtitle: Text(l.settingsReportsHint),
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
                // Язык выбирается явно, а не только берётся из системы:
                // телефон бухгалтера может стоять на русском, а мастера —
                // на узбекском, и приложение у обоих одно.
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l.settingsLanguage),
                  trailing: DropdownButton<String?>(
                    value: ref.watch(localeControllerProvider)?.languageCode,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(child: Text(l.settingsLanguageSystem)),
                      for (final locale in supportedLocales)
                        DropdownMenuItem(
                          value: locale.languageCode,
                          child: Text(_languageName(locale.languageCode)),
                        ),
                    ],
                    onChanged: (code) => ref
                        .read(localeControllerProvider.notifier)
                        .select(code == null ? null : Locale(code)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(l.settingsChangePassword),
                  onTap: () => _changePassword(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(l.settingsServer),
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
                l.settingsLogout,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => _logout(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  /// Название языка пишется на нём самом: человек, который не читает
  /// по-узбекски, всё равно узнает «Русский» в списке.
  String _languageName(String code) => switch (code) {
    'uz' => "O'zbekcha",
    _ => 'Русский',
  };

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
      ).showSnackBar(SnackBar(content: Text(L.of(context).passwordChanged)));
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.of(dialogContext).settingsLogoutQuestion),
        content: Text(L.of(dialogContext).settingsLogoutHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.of(dialogContext).actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.of(dialogContext).settingsLogout),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Роутер уведёт на вход сам, как только сессия станет null.
    await ref.read(sessionControllerProvider.notifier).logout();
  }
}
