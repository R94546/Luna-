import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../../costing/presentation/costing_screen.dart';
import '../data/catalog_dto.dart';
import 'providers/catalog_provider.dart';
import 'widgets/employee_dialog.dart';
import 'widgets/operation_dialog.dart';
import 'widgets/piece_rate_dialog.dart';
import 'widgets/product_dialog.dart';
import 'widgets/stock_movement_dialog.dart';
import 'widgets/telegram_link_dialog.dart';
import '../../../l10n/app_localizations.dart';

/// Справочники: модели, сотрудники, операции, расценки.
///
/// Четыре вкладки в одном разделе, а не четыре пункта навигации: их
/// заполняют один раз при запуске и потом почти не трогают, а место внизу
/// нужно тому, что открывают каждый день.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.catalogTitle),
          actions: [
            // Калькулятор живёт здесь, а не отдельным разделом: он считает
            // по расценкам и моделям из соседних вкладок, и материалы для
            // него — такой же справочник.
            IconButton(
              icon: const Icon(Icons.calculate_outlined),
              tooltip: l.costingTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CostingScreen()),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.catalogProducts),
              Tab(text: l.catalogEmployees),
              Tab(text: l.catalogOperations),
              Tab(text: l.catalogRates),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProductsTab(),
            _EmployeesTab(),
            _OperationsTab(),
            _PieceRatesTab(),
          ],
        ),
      ),
    );
  }
}

// ── Модели ──────────────────────────────────────────────────────────────────

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final products = ref.watch(catalogProductsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'product',
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueBuilder(
        value: products,
        onRetry: () => ref.invalidate(catalogProductsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: l.catalogProductsEmptyTitle,
              message: l.catalogProductsEmptyHint,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(catalogProductsProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final product = list[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${product.sku} · ${product.name}'),
                    subtitle: Text(
                      '${Money.format(product.salePrice)} · '
                      '${l.salesStockLeft(product.stockQuantity)}',
                      style: product.isLowStock
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => switch (value) {
                        'edit' => _edit(context, ref, product),
                        'stock' => _move(context, ref, product),
                        _ => _archive(context, ref, product),
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l.actionEdit)),
                        PopupMenuItem(
                          value: 'stock',
                          child: Text(l.catalogStock),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(l.actionArchive),
                        ),
                      ],
                    ),
                    onTap: () => _edit(context, ref, product),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ProductDto? product,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductDialog(product: product),
    );

    if (saved == true) ref.invalidate(catalogProductsProvider);
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    ProductDto product,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StockMovementDialog(product: product),
    );

    if (saved == true) ref.invalidate(catalogProductsProvider);
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    ProductDto product,
  ) async {
    final confirmed = await _confirm(
      context,
      title: L.of(context).productArchiveQuestion,
      message: L.of(context).productArchiveHint(product.name),
    );

    if (!confirmed || !context.mounted) return;

    await _run(
      context,
      () => ref.read(catalogApiProvider).archiveProduct(product.id),
      onDone: () => ref.invalidate(catalogProductsProvider),
    );
  }
}

// ── Сотрудники ──────────────────────────────────────────────────────────────

class _EmployeesTab extends ConsumerWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final employees = ref.watch(catalogEmployeesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'employee',
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.person_add_alt),
      ),
      body: AsyncValueBuilder(
        value: employees,
        onRetry: () => ref.invalidate(catalogEmployeesProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: l.catalogEmployeesEmptyTitle,
              message: l.catalogEmployeesEmptyHint,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(catalogEmployeesProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final employee = list[index];
                final operation = employee.defaultOperation?.name;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(employee.fullName),
                    subtitle: Text(
                      [
                        if (employee.position?.isNotEmpty ?? false)
                          employee.position!,
                        if (operation != null && operation.isNotEmpty)
                          operation,
                        if (employee.phone?.isNotEmpty ?? false)
                          employee.phone!,
                      ].join(' · '),
                    ),
                    leading: Icon(
                      employee.telegramLinked
                          ? Icons.telegram
                          : Icons.person_outline,
                      // Без Telegram рабочий не отчитывается — это главное,
                      // что мастеру нужно видеть в списке.
                      color: employee.telegramLinked
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => switch (value) {
                        'edit' => _edit(context, ref, employee),
                        'link' => _link(context, ref, employee),
                        'unlink' => _unlink(context, ref, employee),
                        _ => _fire(context, ref, employee),
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l.actionEdit)),
                        if (employee.telegramLinked)
                          PopupMenuItem(
                            value: 'unlink',
                            child: Text(l.telegramUnlink),
                          )
                        else
                          PopupMenuItem(
                            value: 'link',
                            child: Text(l.telegramLink),
                          ),
                        PopupMenuItem(
                          value: 'fire',
                          child: Text(l.employeeFire),
                        ),
                      ],
                    ),
                    onTap: () => _edit(context, ref, employee),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    EmployeeDto? employee,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EmployeeDialog(employee: employee),
    );

    if (saved == true) ref.invalidate(catalogEmployeesProvider);
  }

  Future<void> _link(
    BuildContext context,
    WidgetRef ref,
    EmployeeDto employee,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => TelegramLinkDialog(employee: employee),
    );

    // Привязка происходит в боте, а не здесь: список перечитываем, чтобы
    // отметка появилась, если рабочий успел ввести код.
    ref.invalidate(catalogEmployeesProvider);
  }

  Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    EmployeeDto employee,
  ) async {
    final confirmed = await _confirm(
      context,
      title: L.of(context).telegramUnlinkQuestion,
      message: L.of(context).employeeUnlinkHint(employee.fullName),
    );

    if (!confirmed || !context.mounted) return;

    await _run(
      context,
      () => ref.read(catalogApiProvider).unlinkTelegram(employee.id),
      onDone: () => ref.invalidate(catalogEmployeesProvider),
    );
  }

  Future<void> _fire(
    BuildContext context,
    WidgetRef ref,
    EmployeeDto employee,
  ) async {
    final confirmed = await _confirm(
      context,
      title: L.of(context).employeeFireQuestion,
      message: L.of(context).employeeFireHint(employee.fullName),
    );

    if (!confirmed || !context.mounted) return;

    await _run(
      context,
      () => ref.read(catalogApiProvider).fireEmployee(employee.id),
      onDone: () => ref.invalidate(catalogEmployeesProvider),
    );
  }
}

// ── Операции ────────────────────────────────────────────────────────────────

class _OperationsTab extends ConsumerWidget {
  const _OperationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final operations = ref.watch(catalogOperationsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'operation',
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueBuilder(
        value: operations,
        onRetry: () => ref.invalidate(catalogOperationsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.handyman_outlined,
              title: l.catalogOperationsEmptyTitle,
              message: l.catalogOperationsEmptyHint,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(catalogOperationsProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final operation = list[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(operation.name),
                    subtitle: operation.code?.isNotEmpty ?? false
                        ? Text(operation.code!)
                        : null,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => value == 'edit'
                          ? _edit(context, ref, operation)
                          : _archive(context, ref, operation),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(l.actionEdit)),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(l.actionArchive),
                        ),
                      ],
                    ),
                    onTap: () => _edit(context, ref, operation),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    OperationDto? operation,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => OperationDialog(operation: operation),
    );

    if (saved == true) ref.invalidate(catalogOperationsProvider);
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    OperationDto operation,
  ) async {
    final confirmed = await _confirm(
      context,
      title: L.of(context).productArchiveQuestion,
      message: L.of(context).operationArchiveHint(operation.name),
    );

    if (!confirmed || !context.mounted) return;

    await _run(
      context,
      () => ref.read(catalogApiProvider).archiveOperation(operation.id),
      onDone: () => ref.invalidate(catalogOperationsProvider),
    );
  }
}

// ── Расценки ────────────────────────────────────────────────────────────────

class _PieceRatesTab extends ConsumerWidget {
  const _PieceRatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final rates = ref.watch(pieceRatesProvider);
    final role = ref.watch(sessionControllerProvider).value?.role;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'rate',
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueBuilder(
        value: rates,
        onRetry: () => ref.invalidate(pieceRatesProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.price_change_outlined,
              title: l.catalogRatesEmptyTitle,
              message: l.catalogRatesEmptyHint,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pieceRatesProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final rate = list[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      '${rate.operation.name} · ${Money.format(rate.rate)}',
                    ),
                    subtitle: Text(
                      '${rate.product?.name ?? l.catalogAllProducts} · '
                      '${rate.employee?.fullName ?? l.catalogAllEmployees}',
                    ),
                    // Удаление ставки — правка того, по чему считалась
                    // зарплата, поэтому оно только у владельца.
                    trailing: (role?.canSeeDashboard ?? false)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, ref, rate),
                          )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const PieceRateDialog(),
    );

    if (saved == true) ref.invalidate(pieceRatesProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PieceRateDto rate,
  ) async {
    final confirmed = await _confirm(
      context,
      title: L.of(context).rateDeleteQuestion,
      message: L.of(context).rateDeleteHint,
    );

    if (!confirmed || !context.mounted) return;

    await _run(
      context,
      () => ref.read(catalogApiProvider).deletePieceRate(rate.id),
      onDone: () => ref.invalidate(pieceRatesProvider),
    );
  }
}

// ── Общее ───────────────────────────────────────────────────────────────────

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(L.of(dialogContext).actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(L.of(dialogContext).actionYes),
        ),
      ],
    ),
  );

  return answer ?? false;
}

/// Запрос, у которого нет своей формы: ошибку показываем строкой снизу.
Future<void> _run(
  BuildContext context,
  Future<void> Function() action, {
  required VoidCallback onDone,
}) async {
  try {
    await action();
    onDone();
  } on ApiException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
