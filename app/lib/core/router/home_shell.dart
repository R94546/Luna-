import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/user_role.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/work_logs/presentation/work_logs_screen.dart';

/// Раздел приложения в нижней навигации.
class _Section {
  const _Section({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

/// Оболочка с нижней навигацией.
///
/// Состав вкладок зависит от роли: дашборд на бэкенде закрыт всем, кроме
/// владельца, и показывать мастеру вкладку, которая ответит 403, — значит
/// обещать то, чего нет.
///
/// Экраны держатся в IndexedStack: переключение вкладок не должно
/// перезагружать список выработки и терять прокрутку.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  List<_Section> _sectionsFor(UserRole? role) {
    return [
      if (role?.canSeeDashboard ?? false)
        const _Section(
          label: 'Главная',
          icon: Icons.insights_outlined,
          selectedIcon: Icons.insights,
          screen: DashboardScreen(),
        ),
      const _Section(
        label: 'Выработка',
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        screen: WorkLogsScreen(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionControllerProvider).value?.role;
    // Выработка доступна всем ролям, поэтому список никогда не пуст.
    final sections = _sectionsFor(role);

    // Роль могла смениться (перезаход другим пользователем) — индекс
    // за пределами списка уронил бы IndexedStack.
    final index = _index.clamp(0, sections.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [for (final section in sections) section.screen],
      ),
      // Одна вкладка — это не навигация, а лишняя полоса внизу.
      bottomNavigationBar: sections.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: [
                for (final section in sections)
                  NavigationDestination(
                    icon: Icon(section.icon),
                    selectedIcon: Icon(section.selectedIcon),
                    label: section.label,
                  ),
              ],
            ),
    );
  }
}
