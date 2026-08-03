import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/format/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/dashboard_dto.dart';

/// График выручки и прибыли по дням.
class RevenueChart extends StatelessWidget {
  const RevenueChart({required this.points, super.key});

  final List<ChartPointDto> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.isEmpty) {
      return Card(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              'За период продаж не было',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        ),
      );
    }

    // Одна точка линией не рисуется — показываем её как есть.
    final revenue = <FlSpot>[];
    final profit = <FlSpot>[];

    for (var i = 0; i < points.length; i++) {
      revenue.add(
        FlSpot(i.toDouble(), Money.parse(points[i].revenue).toDouble()),
      );
      profit.add(
        FlSpot(i.toDouble(), Money.parse(points[i].profit).toDouble()),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  _Legend(color: theme.colorScheme.primary, label: 'Выручка'),
                  const SizedBox(width: 16),
                  const _Legend(color: AppTheme.positive, label: 'Прибыль'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.colorScheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (value, _) => Text(
                          Money.compact(value.round().toString()),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        // Подписываем не каждый день: на месяце тридцать
                        // дат превратятся в нечитаемую кашу.
                        interval: (points.length / 4).ceilToDouble(),
                        getTitlesWidget: (value, _) {
                          final index = value.round();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              points[index].date.substring(8),
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    _line(revenue, theme.colorScheme.primary),
                    _line(profit, AppTheme.positive),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 2.5,
      isCurved: true,
      // Кривая не должна уходить ниже нуля на подъёмах — отрицательной
      // выручки не бывает, а сглаживание её нарисует.
      preventCurveOverShooting: true,
      dotData: FlDotData(show: spots.length <= 10),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.08),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
