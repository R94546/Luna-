import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../data/cash_dto.dart';
import 'providers/cash_provider.dart';
import 'widgets/expense_dialog.dart';
import 'widgets/manual_transaction_dialog.dart';
import '../../../l10n/app_localizations.dart';

enum _Tab { summary, journal, expenses }

class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  _Tab _tab = _Tab.summary;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.cashTitle)),
      floatingActionButton: _tab == _Tab.summary
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: Text(
                _tab == _Tab.expenses ? l.cashExpense : l.cashOperationShort,
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<_Tab>(
              segments: [
                ButtonSegment(
                  value: _Tab.summary,
                  label: Text(l.cashTabSummary),
                ),
                ButtonSegment(
                  value: _Tab.journal,
                  label: Text(l.cashTabJournal),
                ),
                ButtonSegment(
                  value: _Tab.expenses,
                  label: Text(l.cashTabExpenses),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _Tab.summary => const _SummaryView(),
              _Tab.journal => const _JournalView(),
              _Tab.expenses => const _ExpensesView(),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _tab == _Tab.expenses
          ? const ExpenseDialog()
          : const ManualTransactionDialog(),
    );

    if (created == true) invalidateMoney(ref);
  }
}

class _SummaryView extends ConsumerWidget {
  const _SummaryView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final summary = ref.watch(cashSummaryProvider);
    final theme = Theme.of(context);

    return AsyncValueBuilder(
      value: summary,
      onRetry: () => ref.invalidate(cashSummaryProvider),
      builder: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(cashSummaryProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            for (final account in data.accounts)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(account.name),
                  trailing: Text(
                    Money.format(account.balance),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _Line(
                      label: l.cashOpeningBalance,
                      value: data.openingBalance,
                    ),
                    _Line(
                      label: l.cashIncome,
                      value: data.income.total,
                      color: AppTheme.positive,
                    ),
                    _Line(
                      label: l.cashOutcome,
                      value: data.outcome.total,
                      color: AppTheme.negative,
                    ),
                    const Divider(height: 24),
                    _Line(
                      label: l.cashClosingBalance,
                      value: data.closingBalance,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            if (data.outcome.byCategory.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(l.cashWhereMoneyWent, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final row in data.outcome.byCategory)
                      ListTile(
                        dense: true,
                        title: Text(row.name),
                        trailing: Text(Money.format(row.amount)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JournalView extends ConsumerWidget {
  const _JournalView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(cashJournalProvider);

    return AsyncValueBuilder(
      value: journal,
      onRetry: () => ref.invalidate(cashJournalProvider),
      builder: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(cashJournalProvider),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          itemCount: data.items.length,
          itemBuilder: (context, index) =>
              _TransactionTile(transaction: data.items[index]),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final CashTransactionDto transaction;

  @override
  Widget build(BuildContext context) {
    final income = transaction.direction == CashDirection.income;
    final color = income ? AppTheme.positive : AppTheme.negative;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          income ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: color,
        ),
        title: Text(
          transaction.note?.isNotEmpty == true
              ? transaction.note!
              : transaction.categoryName,
        ),
        subtitle: Text(
          '${transaction.account.name} · '
          '${_date(transaction.occurredAt)}',
        ),
        trailing: Text(
          '${income ? '+' : '−'} ${Money.format(transaction.amount)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}';
}

class _ExpensesView extends ConsumerWidget {
  const _ExpensesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);

    return AsyncValueBuilder(
      value: expenses,
      onRetry: () => ref.invalidate(expensesProvider),
      builder: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(expensesProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          children: [
            Card(
              child: ListTile(
                title: Text(L.of(context).cashPeriodTotal),
                trailing: Text(
                  Money.format(data.summary.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final expense in data.items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(expense.category.name),
                  subtitle: Text(
                    expense.note?.isNotEmpty == true
                        ? expense.note!
                        : _date(expense.spentAt),
                  ),
                  trailing: Text(
                    Money.format(expense.amount),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(
            Money.format(value),
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
