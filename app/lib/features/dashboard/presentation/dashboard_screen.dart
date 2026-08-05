import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../data/dashboard_api.dart';
import '../data/dashboard_dto.dart';
import 'providers/dashboard_provider.dart';
import 'widgets/alerts_row.dart';
import 'widgets/metric_card.dart';
import 'widgets/revenue_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardPeriod _period = DashboardPeriod.month;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).value;
    final l = L.of(context);
    final data = ref.watch(dashboardProvider(_period));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session?.companyName ?? 'Luna'),
            if (session != null)
              Text(
                session.fullName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.settingsLogout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(sessionControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodSelector(
            value: _period,
            onChanged: (value) => setState(() => _period = value),
          ),
          Expanded(
            child: AsyncValueBuilder(
              value: data,
              onRetry: () => ref.invalidate(dashboardProvider(_period)),
              builder: (dashboard) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(dashboardProvider(_period)),
                child: _Content(dashboard: dashboard),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final DashboardPeriod value;
  final ValueChanged<DashboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SegmentedButton<DashboardPeriod>(
        segments: [
          for (final period in DashboardPeriod.values)
            ButtonSegment(
              value: period,
              label: Text(period.label(L.of(context))),
            ),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.dashboard});

  final DashboardDto dashboard;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return ListView(
      // Всегда прокручиваемый: иначе pull-to-refresh не сработает
      // на коротком экране, где содержимое влезло целиком.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(
          dashboard.period.label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        AlertsRow(alerts: dashboard.alerts),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Высота фиксированная, а не пропорция от ширины: при пропорции
          // карточка на узком экране становится ниже своего содержимого
          // и переполняется, а на планшете растягивается на пол-экрана.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 118,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          children: [
            MetricCard(title: l.dashRevenue, metric: dashboard.revenue),
            MetricCard(title: l.dashGrossProfit, metric: dashboard.grossProfit),
            MetricCard(title: l.dashNetProfit, metric: dashboard.netProfit),
            MetricCard(
              title: l.dashExpenses,
              metric: dashboard.expenses,
              higherIsBetter: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: MetricCard(
            title: l.dashSalaryPaid,
            metric: dashboard.salaries,
            higherIsBetter: false,
          ),
        ),
        const SizedBox(height: 16),
        RevenueChart(points: dashboard.revenueChart),
        const SizedBox(height: 16),
        _MoneyRow(
          left: _Tile(
            title: l.dashCash,
            value: Money.format(dashboard.cashBalance),
            icon: Icons.account_balance_wallet_outlined,
          ),
          right: _Tile(
            title: l.dashSalaryDebt,
            value: Money.format(dashboard.salaryDebt),
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(height: 12),
        _MoneyRow(
          left: _Tile(
            title: l.dashProduced,
            value: l.pairs(dashboard.unitsProduced),
            icon: Icons.precision_manufacturing_outlined,
          ),
          right: _Tile(
            title: l.dashSold,
            value: l.pairs(dashboard.unitsSold),
            icon: Icons.local_shipping_outlined,
          ),
        ),
        if (dashboard.topProducts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l.dashTopProducts,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final product in dashboard.topProducts)
                  _TopProductTile(product: product),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
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
        ),
      ),
    );
  }
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({required this.product});

  final TopProductDto product;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(product.name),
      subtitle: Text(L.of(context).pairs(product.unitsSold)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.compact(product.revenue),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            L.of(context).dashProfitShort(Money.compact(product.profit)),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
