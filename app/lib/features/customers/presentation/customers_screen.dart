import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../data/customer_dto.dart';
import 'providers/customers_provider.dart';
import 'widgets/customer_dialog.dart';
import '../../../l10n/app_localizations.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final customers = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.customersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.person_add_alt),
        label: Text(l.customersOne),
      ),
      body: AsyncValueBuilder(
        value: customers,
        onRetry: () => ref.invalidate(customersProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: l.customersEmptyTitle,
              message: l.customersEmptyHint,
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(customersProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final customer = list[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(customer.name),
                    subtitle: customer.phone?.isNotEmpty ?? false
                        ? Text(customer.phone!)
                        : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, ref, customer),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    CustomerDto customer,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _CustomerSheet(customer: customer),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CustomerDto? customer,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerDialog(customer: customer),
    );

    if (saved == true) ref.invalidate(customersProvider);
  }
}

/// Карточка клиента: долг, обороты, активные заказы.
class _CustomerSheet extends ConsumerWidget {
  const _CustomerSheet({required this.customer});

  final CustomerDto customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(customerDetailProvider(customer.id));
    final theme = Theme.of(context);
    final role = ref.watch(sessionControllerProvider).value?.role;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: AsyncValueBuilder(
          value: detail,
          onRetry: () => ref.invalidate(customerDetailProvider(customer.id)),
          builder: (data) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(data.name, style: theme.textTheme.titleLarge),
              if (data.phone?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(data.phone!, style: theme.textTheme.bodyMedium),
              ],
              if (data.note?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(data.note!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),
              _Row(
                label: L.of(context).customersDebt,
                value: Money.format(data.debt),
                // Красным — только когда должны на самом деле: ноль,
                // выделенный тревожным цветом, читается как проблема.
                accent: Money.parse(data.debt) > Decimal.zero,
              ),
              _Row(
                label: L.of(context).customersBought,
                value: Money.format(data.totalAmount),
              ),
              _Row(
                label: L.of(context).customersSalesCount,
                value: '${data.salesCount}',
              ),
              _Row(
                label: L.of(context).customersActiveOrders,
                value: '${data.activeOrders}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _edit(context, ref),
                      child: Text(L.of(context).actionEdit),
                    ),
                  ),
                  // Архивировать может только владелец: на клиента ссылаются
                  // продажи и заказы.
                  if (role?.canSeeDashboard ?? false) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _archive(context, ref),
                        child: Text(L.of(context).actionArchive),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CustomerDialog(customer: customer),
    );

    if (saved != true) return;

    ref
      ..invalidate(customersProvider)
      ..invalidate(customerDetailProvider(customer.id));
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(customersApiProvider).archive(customer.id);
      ref.invalidate(customersProvider);

      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
