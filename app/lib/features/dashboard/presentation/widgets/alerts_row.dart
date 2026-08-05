import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/dashboard_dto.dart';

/// То, что требует внимания прямо сейчас.
///
/// Показывается только непустое: строка «просроченных заказов: 0» занимает
/// место и приучает не читать этот блок вовсе.
class AlertsRow extends StatelessWidget {
  const AlertsRow({required this.alerts, super.key});

  final AlertsDto alerts;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final items = <Widget>[
      if (alerts.pendingWorkLogs > 0)
        _Alert(
          icon: Icons.pending_actions_outlined,
          label: l.dashAlertWorkLogs,
          count: alerts.pendingWorkLogs,
          color: AppTheme.warning,
        ),
      if (alerts.lowStockProducts > 0)
        _Alert(
          icon: Icons.inventory_2_outlined,
          label: l.dashAlertLowStock,
          count: alerts.lowStockProducts,
          color: AppTheme.warning,
        ),
      if (alerts.overdueOrders > 0)
        _Alert(
          icon: Icons.schedule_outlined,
          label: l.dashAlertOrdersOverdue,
          count: alerts.overdueOrders,
          color: AppTheme.negative,
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[item, const SizedBox(height: 8)],
      ],
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
