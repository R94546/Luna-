import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/dashboard_dto.dart';

/// Карточка показателя: сумма и её динамика.
///
/// Абсолютная цифра без сравнения владельцу мало что говорит — 84 миллиона
/// выручки это хорошо или плохо, видно только рядом с прошлым периодом.
class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.title,
    required this.metric,
    this.higherIsBetter = true,
    super.key,
  });

  final String title;
  final MetricDto metric;

  /// Для расходов и зарплаты рост — это плохо, и красить его зелёным
  /// значило бы поздравлять владельца с тем, что он больше потратил.
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final change = metric.changePercent;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.compact(metric.value),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _Change(percent: change, higherIsBetter: higherIsBetter),
          ],
        ),
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.percent, required this.higherIsBetter});

  final double? percent;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    // Прочерк вместо стрелки: сравнивать не с чем, и рисовать «0%»
    // означало бы утверждать, что ничего не изменилось.
    if (percent == null) {
      return Text(
        '—',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      );
    }

    final value = percent!;
    final grew = value > 0;
    final good = grew == higherIsBetter;

    final color = value == 0
        ? Theme.of(context).colorScheme.outline
        : good
        ? AppTheme.positive
        : AppTheme.negative;

    return Row(
      children: [
        if (value != 0)
          Icon(
            grew ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 14,
            color: color,
          ),
        const SizedBox(width: 2),
        Text(
          Money.change(value),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
