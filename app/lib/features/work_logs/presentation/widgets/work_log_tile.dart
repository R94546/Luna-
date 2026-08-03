import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/work_log_dto.dart';

/// Строка выработки.
///
/// Первым делом — кто и сколько сделал: мастер подтверждает отчёты пачкой
/// и смотрит именно на эту пару. Модель и операция мельче, сумма справа.
class WorkLogTile extends StatelessWidget {
  const WorkLogTile({
    required this.log,
    required this.selectable,
    required this.selected,
    this.onTap,
    this.onLongPress,
    this.onApprove,
    this.onReject,
    super.key,
  });

  final WorkLogDto log;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = log.status == WorkLogStatus.pending;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectable) ...[
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.employee.fullName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${log.product.name} · ${log.operation.name}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${log.quantity} пар',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Money.format(log.amount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Badge(status: log.status),
                  const SizedBox(width: 8),
                  if (log.source == 'TELEGRAM')
                    Icon(
                      Icons.send_rounded,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(log.workDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  // Кнопки только у ждущих записей и только когда не идёт
                  // выбор пачкой — иначе два способа сделать одно и то же
                  // на одном экране.
                  if (pending && !selectable && onApprove != null) ...[
                    TextButton(
                      onPressed: onReject,
                      child: const Text('Отклонить'),
                    ),
                    FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('Принять'),
                    ),
                  ],
                ],
              ),
              if (log.rejectReason != null && log.rejectReason!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Причина: ${log.rejectReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.negative,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});

  final WorkLogStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WorkLogStatus.pending => AppTheme.warning,
      WorkLogStatus.approved => AppTheme.positive,
      WorkLogStatus.rejected => AppTheme.negative,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
