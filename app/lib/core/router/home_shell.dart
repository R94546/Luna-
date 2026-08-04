import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/user_role.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../../features/cash/presentation/cash_screen.dart';
import '../../features/catalog/presentation/catalog_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/orders/presentation/orders_screen.dart';
import '../../features/payroll/presentation/payroll_screen.dart';
import '../../features/sales/presentation/sales_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
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
      // Заказы ведёт мастер: это про производство, а не про деньги.
      const _Section(
        label: 'Заказы',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        screen: OrdersScreen(),
      ),
      // Зарплата, продажи и касса — зона владельца и бухгалтера. Мастер их
      // не видит: на бэкенде эти эндпоинты ему закрыты.
      if (role?.canSeeMoney ?? false) ...[
        const _Section(
          label: 'Продажи',
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          screen: SalesScreen(),
        ),
        const _Section(
          label: 'Зарплата',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments,
          screen: PayrollScreen(),
        ),
        const _Section(
          label: 'Деньги',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: CashScreen(),
        ),
      ],
      // Справочники и клиенты стоят после ежедневных разделов намеренно:
      // их заполняют при запуске цеха и потом почти не открывают.
      if (role?.canManageCatalog ?? false)
        const _Section(
          label: 'Справочники',
          icon: Icons.category_outlined,
          selectedIcon: Icons.category,
          screen: CatalogScreen(),
        ),
      const _Section(
        label: 'Клиенты',
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        screen: CustomersScreen(),
      ),
      const _Section(
        label: 'Настройки',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        screen: SettingsScreen(),
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
          : _BottomBar(
              sections: sections,
              index: index,
              onSelected: (value) => setState(() => _index = value),
            ),
    );
  }
}

/// Нижняя навигация.
///
/// Больше пяти иконок в ряд на телефоне не помещаются: подписи обрезаются
/// и попасть пальцем становится трудно. Поэтому при шести и более разделах
/// последняя кнопка превращается в «Ещё» со списком остальных.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.sections,
    required this.index,
    required this.onSelected,
  });

  final List<_Section> sections;
  final int index;
  final ValueChanged<int> onSelected;

  static const _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    if (sections.length <= _maxVisible) {
      return NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelected,
        destinations: [
          for (final section in sections)
            NavigationDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: section.label,
            ),
        ],
      );
    }

    final visible = sections.take(_maxVisible - 1).toList();
    final hidden = sections.skip(_maxVisible - 1).toList();
    final inHidden = index >= visible.length;

    return NavigationBar(
      // Когда открыт скрытый раздел, подсвечиваем «Ещё».
      selectedIndex: inHidden ? visible.length : index,
      onDestinationSelected: (value) {
        if (value < visible.length) {
          onSelected(value);
          return;
        }
        _showMore(context, hidden);
      },
      destinations: [
        for (final section in visible)
          NavigationDestination(
            icon: Icon(section.icon),
            selectedIcon: Icon(section.selectedIcon),
            label: section.label,
          ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz),
          // Подписываем текущим разделом, чтобы человек видел, где он.
          label: inHidden ? sections[index].label : 'Ещё',
        ),
      ],
    );
  }

  void _showMore(BuildContext context, List<_Section> hidden) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final section in hidden)
              ListTile(
                leading: Icon(section.icon),
                title: Text(section.label),
                selected: sections.indexOf(section) == index,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSelected(sections.indexOf(section));
                },
              ),
          ],
        ),
      ),
    );
  }
}
