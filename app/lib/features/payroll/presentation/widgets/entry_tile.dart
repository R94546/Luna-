import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/payroll_dto.dart';
import '../../../../l10n/app_localizations.dart';

/// Строка ведомости.
///
/// Показываются и начисленное, и к выплате: аванс уменьшает второе, но не
/// первое, и владелец, увидев одну цифру вместо двух, решит, что человеку
/// недоплатили.
class EntryTile extends StatelessWidget {
  const EntryTile({
    required this.entry,
    required this.editable,
    this.onEdit,
    this.onPay,
    super.key,
  });

  final PayrollEntryDto entry;
  final bool editable;
  final VoidCallback? onEdit;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final theme = Theme.of(context);
    final negative = (double.tryParse(entry.toPay) ?? 0) < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.employee.fullName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (entry.isPaid)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppTheme.positive,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _Row(label: l.payrollWork, value: entry.workAmount),
            if (entry.bonus != '0' && Money.parse(entry.bonus).sign != 0)
              _Row(
                label: l.payrollBonus,
                value: entry.bonus,
                color: AppTheme.positive,
              ),
            if (Money.parse(entry.deduction).sign != 0)
              _Row(
                label: l.payrollDeduction,
                value: entry.deduction,
                color: AppTheme.negative,
              ),
            if (Money.parse(entry.advancePaid).sign != 0)
              _Row(label: l.payrollAdvanceGiven, value: entry.advancePaid),
            const Divider(height: 20),
            Row(
              children: [
                Text(l.payrollToPay, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  Money.format(entry.toPay),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    // Минус означает переплаченный аванс — это долг
                    // работника, и он должен бросаться в глаза.
                    color: negative ? AppTheme.negative : null,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (editable && onEdit != null)
                  TextButton(
                    onPressed: onEdit,
                    child: Text(l.payrollBonusOrDeduction),
                  ),
                if (onPay != null)
                  TextButton(onPressed: onPay, child: Text(l.payrollPay)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
