import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/payroll_dto.dart';
import 'period_detail_screen.dart';
import 'providers/payroll_provider.dart';

class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(payrollPeriodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Зарплата')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPeriod(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Открыть период'),
      ),
      body: AsyncValueBuilder(
        value: periods,
        onRetry: () => ref.invalidate(payrollPeriodsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Периодов нет',
              message:
                  'Откройте период — начисления соберутся из подтверждённой '
                  'выработки автоматически',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(payrollPeriodsProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _PeriodCard(period: items[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPeriod(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1, 0),
      ),
      helpText: 'Период начисления',
    );

    if (range == null || !context.mounted) return;

    try {
      final period = await ref
          .read(payrollApiProvider)
          .createPeriod(
            periodStart: _date(range.start),
            periodEnd: _date(range.end),
          );

      ref.invalidate(payrollPeriodsProvider);

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PeriodDetailScreen(periodId: period.periodId),
        ),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period});

  final PeriodSummaryDto period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          '${_short(period.periodStart)} — ${_short(period.periodEnd)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${period.employeeCount} сотрудников'),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Money.compact(period.totalAmount),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _StatusChip(status: period.status),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PeriodDetailScreen(periodId: period.id),
          ),
        ),
      ),
    );
  }

  /// «2026-08-01» → «01.08».
  static String _short(String isoDate) {
    final parts = isoDate.split('-');
    return parts.length == 3 ? '${parts[2]}.${parts[1]}' : isoDate;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PayrollPeriodStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (status) {
      PayrollPeriodStatus.open => scheme.primary,
      PayrollPeriodStatus.closed => scheme.outline,
      PayrollPeriodStatus.paid => const Color(0xFF12A150),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
