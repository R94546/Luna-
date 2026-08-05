import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../cash/presentation/providers/cash_provider.dart';
import '../data/order_dto.dart';
import 'orders_screen.dart';
import 'providers/orders_provider.dart';
import 'widgets/issue_dialog.dart';
import 'widgets/progress_dialog.dart';
import '../../../l10n/app_localizations.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final order = ref.watch(orderControllerProvider(orderId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order.valueOrNull == null
              ? l.ordersOrder
              : l.ordersOrderNumber(order.valueOrNull!.orderNumber),
        ),
      ),
      body: AsyncValueBuilder(
        value: order,
        onRetry: () => ref.invalidate(orderControllerProvider(orderId)),
        builder: (data) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(orderControllerProvider(orderId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Header(order: data),
              const SizedBox(height: 16),
              Text(
                l.ordersItems,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final item in data.items) _ItemTile(item: item),
              const SizedBox(height: 20),
              _Actions(
                order: data,
                onProgress: () => _editProgress(context, ref, data),
                onTransition: (status) =>
                    _transition(context, ref, data, status),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProgress(
    BuildContext context,
    WidgetRef ref,
    OrderDto order,
  ) async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => ProgressDialog(order: order),
    );

    if (result == null || !context.mounted) return;

    await _guard(
      context,
      () => ref
          .read(orderControllerProvider(orderId).notifier)
          .updateProgress(result),
    );
  }

  /// Переход статуса.
  ///
  /// Выдача — единственный переход с последствиями: товар уходит со склада,
  /// и по желанию оформляется продажа. Поэтому у неё отдельный диалог,
  /// а остальные переходы применяются сразу.
  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    OrderDto order,
    OrderStatus status,
  ) async {
    if (status != OrderStatus.issued) {
      await _guard(
        context,
        () => ref
            .read(orderControllerProvider(orderId).notifier)
            .changeStatus(status),
      );
      return;
    }

    final result = await showDialog<IssueResult>(
      context: context,
      builder: (_) => IssueDialog(order: order),
    );

    if (result == null || !context.mounted) return;

    await _guard(context, () async {
      await ref
          .read(orderControllerProvider(orderId).notifier)
          .changeStatus(
            OrderStatus.issued,
            createSale: result.createSale,
            cashAccountId: result.cashAccountId,
            paidAmount: result.paidAmount,
          );

      // Выдача двигает склад, а с продажей — ещё и кассу.
      if (result.createSale) invalidateMoney(ref);
    });
  }

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OrderStatusChip(status: order.status),
                const Spacer(),
                if (order.dueDate != null)
                  Text(
                    L.of(context).ordersDue(order.dueDate ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: order.isOverdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.customer?.name ?? L.of(context).ordersNoCustomer,
              style: theme.textTheme.titleMedium,
            ),
            if (order.customer?.phone != null)
              Text(
                order.customer!.phone!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            const Divider(height: 24),
            _Line(label: l.ordersAmount, value: order.totalAmount),
            _Line(label: l.ordersPrepaid, value: order.prepaidAmount),
            _Line(label: l.ordersDebt, value: order.debt, bold: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  l.ordersProgress,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                Text('${order.progress.percent}%'),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: order.progress.percent / 100,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const Spacer(),
          Text(
            Money.format(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final OrderItemDto item;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item.product.name),
        subtitle: Text(
          L.of(context).ordersProducedOf(item.producedQuantity, item.quantity) +
              Money.format(item.unitPrice),
        ),
        trailing: Text(
          Money.compact(item.total),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Кнопки переходов.
///
/// Список берётся из `availableTransitions` — его считает сервер. Клиент
/// не решает, что можно: иначе автомат статусов оказался бы в двух местах
/// и однажды разошёлся.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.order,
    required this.onProgress,
    required this.onTransition,
  });

  final OrderDto order;
  final VoidCallback onProgress;
  final ValueChanged<OrderStatus> onTransition;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final open =
        order.status != OrderStatus.issued &&
        order.status != OrderStatus.cancelled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (open)
          OutlinedButton.icon(
            onPressed: onProgress,
            icon: const Icon(Icons.checklist_rounded),
            label: Text(l.ordersMarkProduced),
          ),
        for (final status in order.availableTransitions) ...[
          const SizedBox(height: 8),
          if (status == OrderStatus.cancelled)
            OutlinedButton(
              onPressed: () => onTransition(status),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l.ordersCancel),
            )
          else
            FilledButton(
              onPressed: () => onTransition(status),
              child: Text(
                status == OrderStatus.issued ? l.ordersIssue : status.label(l),
              ),
            ),
        ],
      ],
    );
  }
}
