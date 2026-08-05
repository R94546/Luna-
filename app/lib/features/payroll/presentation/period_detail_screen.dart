import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../cash/presentation/providers/cash_provider.dart';
import '../data/payroll_dto.dart';
import 'providers/payroll_provider.dart';
import 'widgets/entry_tile.dart';
import 'widgets/pay_dialog.dart';
import '../../../l10n/app_localizations.dart';

/// Ведомость периода.
class PeriodDetailScreen extends ConsumerWidget {
  const PeriodDetailScreen({required this.periodId, super.key});

  final String periodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final period = ref.watch(periodControllerProvider(periodId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.payrollSheet),
        actions: [
          if (period.valueOrNull?.status.isEditable ?? false) ...[
            IconButton(
              tooltip: l.payrollRecalculate,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _run(
                context,
                () => ref
                    .read(periodControllerProvider(periodId).notifier)
                    .calculate(),
                success: l.payrollRecalculated,
              ),
            ),
            IconButton(
              tooltip: l.payrollClosePeriod,
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: () => _confirmClose(context, ref),
            ),
          ],
        ],
      ),
      body: AsyncValueBuilder(
        value: period,
        onRetry: () => ref.invalidate(periodControllerProvider(periodId)),
        builder: (data) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(periodControllerProvider(periodId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Header(period: data),
              const SizedBox(height: 16),
              if (data.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text(L.of(context).payrollNoApproved)),
                )
              else
                for (final entry in data.entries)
                  EntryTile(
                    entry: entry,
                    editable: data.status.isEditable,
                    onEdit: () => _editEntry(context, ref, entry),
                    onPay: () => _pay(context, ref, data, entry),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (!context.mounted || success == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Закрытие необратимо: выработка получает ссылку на начисление и во
  /// второй период уже не попадёт. Спрашиваем прямо.
  Future<void> _confirmClose(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.of(dialogContext).payrollClosePeriodQuestion),
        content: Text(L.of(dialogContext).payrollClosePeriodHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.of(dialogContext).actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(L.of(dialogContext).actionClose),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await _run(
      context,
      () => ref.read(periodControllerProvider(periodId).notifier).close(),
      success: L.of(context).payrollClosed,
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    WidgetRef ref,
    PayrollEntryDto entry,
  ) async {
    final result = await showDialog<({String bonus, String deduction})>(
      context: context,
      builder: (_) => _EditEntryDialog(entry: entry),
    );

    if (result == null || !context.mounted) return;

    await _run(
      context,
      () => ref
          .read(periodControllerProvider(periodId).notifier)
          .updateEntry(
            entry.id,
            bonus: result.bonus,
            deduction: result.deduction,
          ),
    );
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    PeriodDto period,
    PayrollEntryDto entry,
  ) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => PayDialog(entry: entry, periodId: period.periodId),
    );

    if (paid != true || !context.mounted) return;

    // Деньги ушли из кассы — обновляем и ведомость, и всё денежное.
    await ref.read(periodControllerProvider(periodId).notifier).reload();
    invalidateMoney(ref);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.period});

  final PeriodDto period;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final theme = Theme.of(context);

    final toPay = period.entries.fold<double>(
      0,
      (sum, e) => sum + (double.tryParse(e.toPay) ?? 0),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${period.periodStart} — ${period.periodEnd}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: l.payrollAccrued,
                    value: Money.format(period.totalAmount),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: l.payrollToPay,
                    value: Money.format(toPay.toStringAsFixed(0)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

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
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry});

  final PayrollEntryDto entry;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  late final _bonus = TextEditingController(text: _clean(widget.entry.bonus));
  late final _deduction = TextEditingController(
    text: _clean(widget.entry.deduction),
  );

  /// «40000.00» → «40000»: копеек в цехе нет, а лишние нули мешают править.
  static String _clean(String value) => value.split('.').first;

  @override
  void dispose() {
    _bonus.dispose();
    _deduction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return AlertDialog(
      title: Text(widget.entry.employee.fullName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _bonus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.payrollBonus),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deduction,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.payrollDeduction),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            bonus: _bonus.text.trim().isEmpty ? '0' : _bonus.text.trim(),
            deduction: _deduction.text.trim().isEmpty
                ? '0'
                : _deduction.text.trim(),
          )),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}
