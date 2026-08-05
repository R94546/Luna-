import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/order_dto.dart';
import 'order_detail_screen.dart';
import 'providers/orders_provider.dart';
import '../../../l10n/app_localizations.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final orders = ref.watch(ordersProvider);
    final filter = ref.watch(ordersFilterProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.ordersTitle)),
      body: Column(
        children: [
          _Filter(
            status: filter.status,
            overdue: filter.overdue,
            onStatus: (status) =>
                ref.read(ordersFilterProvider.notifier).setStatus(status),
            onOverdue: () =>
                ref.read(ordersFilterProvider.notifier).showOverdue(),
          ),
          Expanded(
            child: AsyncValueBuilder(
              value: orders,
              onRetry: () => ref.invalidate(ordersProvider),
              builder: (page) {
                if (page.items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inbox_outlined,
                    title: l.ordersEmptyTitle,
                    message: l.ordersEmptyFiltered,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ordersProvider),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: page.items.length,
                    itemBuilder: (context, index) =>
                        _OrderCard(order: page.items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.status,
    required this.overdue,
    required this.onStatus,
    required this.onOverdue,
  });

  final OrderStatus? status;
  final bool overdue;
  final ValueChanged<OrderStatus?> onStatus;
  final VoidCallback onOverdue;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(L.of(context).ordersAll),
            selected: status == null && !overdue,
            onSelected: (_) => onStatus(null),
          ),
          const SizedBox(width: 8),
          // Просроченные отдельной кнопкой: из-за них теряют клиентов,
          // и прятать их в общий список нельзя.
          ChoiceChip(
            label: Text(L.of(context).ordersOverdue),
            selected: overdue,
            onSelected: (_) => onOverdue(),
          ),
          for (final value in [
            OrderStatus.isNew,
            OrderStatus.inProgress,
            OrderStatus.ready,
            OrderStatus.issued,
          ])
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(value.label(L.of(context))),
                selected: status == value && !overdue,
                onSelected: (_) => onStatus(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(orderId: order.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    L.of(context).ordersNumber(order.orderNumber),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OrderStatusChip(status: order.status),
                  if (order.isOverdue) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppTheme.negative,
                    ),
                  ],
                  const Spacer(),
                  Text(
                    Money.compact(order.totalAmount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                order.customer?.name ?? L.of(context).ordersNoCustomer,
                style: theme.textTheme.bodyMedium,
              ),
              if (order.dueDate != null)
                Text(
                  L.of(context).ordersDue(order.dueDate ?? ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: order.isOverdue
                        ? AppTheme.negative
                        : theme.colorScheme.outline,
                  ),
                ),
              const SizedBox(height: 10),
              _Progress(progress: order.progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final ProgressDto progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.percent / 100,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          L.of(context).ordersProgressOf(progress.produced, progress.ordered),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (status) {
      OrderStatus.isNew => scheme.primary,
      OrderStatus.inProgress => AppTheme.warning,
      OrderStatus.ready => AppTheme.positive,
      OrderStatus.issued => scheme.outline,
      OrderStatus.cancelled => AppTheme.negative,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label(L.of(context)),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
