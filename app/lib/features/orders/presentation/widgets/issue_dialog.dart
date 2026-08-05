import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/money.dart';
import '../../../cash/data/cash_dto.dart';
import '../../../cash/presentation/providers/cash_provider.dart';
import '../../../sales/data/sale_dto.dart';
import '../../data/order_dto.dart';
import '../../../../l10n/app_localizations.dart';

/// Что выбрал пользователь при выдаче.
class IssueResult {
  const IssueResult({
    required this.createSale,
    this.cashAccountId,
    this.paidAmount,
  });

  final bool createSale;
  final String? cashAccountId;
  final String? paidAmount;
}

/// Выдача заказа.
///
/// Товар уходит со склада в любом случае. Продажа — по желанию: заказ
/// могли оплатить заранее и провести отдельно. Сервер делает оба действия
/// одной транзакцией и списывает товар ровно одним движением.
class IssueDialog extends ConsumerStatefulWidget {
  const IssueDialog({required this.order, super.key});

  final OrderDto order;

  @override
  ConsumerState<IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends ConsumerState<IssueDialog> {
  bool _createSale = true;
  PaymentMethod _method = PaymentMethod.cash;
  String? _accountId;
  late final _paid = TextEditingController(
    text: Money.parse(widget.order.debt).round().toString(),
  );

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final accounts = ref.watch(cashAccountsProvider);
    final needsAccount = _createSale && _method.needsCashAccount;

    return AlertDialog(
      title: Text(l.ordersIssueTitle(widget.order.orderNumber)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.ordersIssueHint(widget.order.progress.ordered),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _createSale,
              title: Text(l.ordersMakeSale),
              subtitle: Text(l.ordersMoneyToCash),
              onChanged: (value) => setState(() => _createSale = value),
            ),
            if (_createSale) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: InputDecoration(labelText: l.salesPayment),
                items: [
                  for (final method in PaymentMethod.values)
                    DropdownMenuItem(
                      value: method,
                      child: Text(method.label(l)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? PaymentMethod.cash),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paid,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.ordersPrepaid),
              ),
              if (needsAccount) ...[
                const SizedBox(height: 12),
                accounts.when(
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _accountId ?? _pickDefault(list),
                    decoration: InputDecoration(labelText: l.ordersToCash),
                    items: [
                      for (final account in list)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(l.errorLoadCashAccounts),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: needsAccount && _accountId == null
              ? null
              : () => Navigator.of(context).pop(
                  IssueResult(
                    createSale: _createSale,
                    cashAccountId: needsAccount ? _accountId : null,
                    paidAmount: _createSale ? _paid.text.trim() : null,
                  ),
                ),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(l.ordersIssue),
        ),
      ],
    );
  }

  String? _pickDefault(List<CashAccountDto> accounts) {
    if (accounts.isEmpty) return null;

    final preferred = accounts.firstWhere(
      (a) => a.isDefault,
      orElse: () => accounts.first,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _accountId == null) {
        setState(() => _accountId = preferred.id);
      }
    });

    return preferred.id;
  }
}
