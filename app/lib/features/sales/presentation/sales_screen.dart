import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../../cash/presentation/providers/cash_provider.dart';
import '../data/sale_dto.dart';
import 'providers/sales_provider.dart';
import 'widgets/new_sale_sheet.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(salesProvider);
    final role = ref.watch(sessionControllerProvider).value?.role;

    return Scaffold(
      appBar: AppBar(title: const Text('Продажи')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSale(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Продать'),
      ),
      body: AsyncValueBuilder(
        value: sales,
        onRetry: () => ref.invalidate(salesProvider),
        builder: (page) {
          if (page.items.isEmpty) {
            return const EmptyState(
              icon: Icons.point_of_sale_outlined,
              title: 'Продаж нет',
              message:
                  'Оформите первую — товар спишется со склада, '
                  'а деньги придут в кассу',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(salesProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                _Summary(summary: page.summary),
                const SizedBox(height: 12),
                for (final sale in page.items)
                  _SaleCard(
                    sale: sale,
                    // Сторнировать может только владелец: это правка
                    // финансовой истории.
                    onCancel: (role?.canSeeDashboard ?? false)
                        ? () => _cancel(context, ref, sale)
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _newSale(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const NewSaleSheet(),
    );

    if (created == true) {
      ref.invalidate(salesProvider);
      ref.invalidate(productsProvider);
      invalidateMoney(ref);
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    SaleDto sale,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CancelDialog(saleNumber: sale.saleNumber),
    );

    if (reason == null || !context.mounted) return;

    try {
      await ref.read(salesApiProvider).cancel(sale.id, reason);
      ref.invalidate(salesProvider);
      ref.invalidate(productsProvider);
      invalidateMoney(ref);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final SalesSummaryDto summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _Figure(label: 'Выручка', value: summary.revenue),
            ),
            Expanded(
              child: _Figure(
                label: 'Прибыль',
                value: summary.grossProfit,
                color: AppTheme.positive,
              ),
            ),
            if (Money.parse(summary.debt).sign > 0)
              Expanded(
                child: _Figure(
                  label: 'Долг',
                  value: summary.debt,
                  color: AppTheme.negative,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Money.compact(value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, this.onCancel});

  final SaleDto sale;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '№${sale.saleNumber}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    // Сторнированная продажа зачёркнута: она осталась
                    // в истории, но выручкой больше не считается.
                    decoration: sale.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                if (sale.isCancelled)
                  const _Chip(text: 'Сторно', color: AppTheme.negative)
                else
                  _Chip(
                    text: sale.paymentMethod.label,
                    color: theme.colorScheme.outline,
                  ),
                const Spacer(),
                Text(
                  Money.format(sale.totalAmount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              sale.items
                  .map((i) => '${i.product.name} ×${i.quantity}')
                  .join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Прибыль ${Money.compact(sale.grossProfit)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.positive,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (Money.parse(sale.debt).sign > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Долг ${Money.compact(sale.debt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.negative,
                    ),
                  ),
                ],
                const Spacer(),
                if (onCancel != null && !sale.isCancelled)
                  TextButton(onPressed: onCancel, child: const Text('Сторно')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.saleNumber});

  final int saleNumber;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Сторнировать продажу №${widget.saleNumber}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Товар вернётся на склад, деньги — обратной проводкой в кассу. '
            'Продажа останется в истории с отметкой.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 255,
            decoration: const InputDecoration(labelText: 'Причина'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Сторнировать'),
        ),
      ],
    );
  }
}
