import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/session_provider.dart';

/// Экран для ролей, чьи разделы ещё не сделаны.
///
/// Мастер и бухгалтер входят в систему уже сейчас, но дашборд им закрыт
/// на бэкенде. Показать им пустоту или чужой 403 хуже, чем честно сказать,
/// что их раздел на подходе.
class PlaceholderScreen extends ConsumerWidget {
  const PlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.companyName ?? 'Luna'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 56,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 20),
              Text(
                session == null
                    ? 'Раздел в разработке'
                    : 'Здравствуйте, ${session.fullName}',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Раздел «${session?.role.label ?? ''}» появится в следующем '
                'обновлении. Выработку пока принимает Telegram-бот.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
