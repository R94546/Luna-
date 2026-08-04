import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/idempotency.dart';
import '../../../../core/format/money.dart';
import '../../../cash/data/cash_dto.dart';
import '../../../cash/presentation/providers/cash_provider.dart';
import '../../data/sale_dto.dart';
import '../../data/sales_api.dart';
import '../providers/sales_provider.dart';

/// Оформление продажи.
///
/// Ключ идемпотентности создаётся один раз на открытие формы: связь
/// оборвалась, человек жмёт «Продать» снова — повтор уходит с тем же
/// ключом, и товар не спишется дважды.
class NewSaleSheet extends ConsumerStatefulWidget {
  const NewSaleSheet({super.key});

  @override
  ConsumerState<NewSaleSheet> createState() => _NewSaleSheetState();
}

class _NewSaleSheetState extends ConsumerState<NewSaleSheet> {
  final _key = IdempotencyKey();
  final _lines = <String, int>{};

  PaymentMethod _method = PaymentMethod.cash;
  String? _accountId;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final accounts = ref.watch(cashAccountsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Text(
              'Новая продажа',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: products.when(
                data: (list) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final product in list)
                      _ProductRow(
                        product: product,
                        quantity: _lines[product.id] ?? 0,
                        onChanged: (value) => setState(() {
                          if (value <= 0) {
                            _lines.remove(product.id);
                          } else {
                            _lines[product.id] = value;
                          }
                        }),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: _method,
                      decoration: const InputDecoration(labelText: 'Оплата'),
                      items: [
                        for (final method in PaymentMethod.values)
                          DropdownMenuItem(
                            value: method,
                            child: Text(method.label),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                              () => _method = value ?? PaymentMethod.cash,
                            ),
                    ),
                    if (_method.needsCashAccount) ...[
                      const SizedBox(height: 12),
                      accounts.when(
                        data: (accountList) => DropdownButtonFormField<String>(
                          initialValue: _accountId ?? _pickDefault(accountList),
                          decoration: const InputDecoration(
                            labelText: 'В кассу',
                          ),
                          items: [
                            for (final account in accountList)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(account.name),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _accountId = value),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) =>
                            const Text('Не удалось загрузить кассы'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text('Не удалось загрузить товары')),
              ),
            ),
            _Footer(
              total: _total(products.valueOrNull ?? []),
              busy: _busy,
              enabled: _lines.isNotEmpty,
              onSubmit: () => _submit(products.valueOrNull ?? []),
            ),
          ],
        ),
      ),
    );
  }

  /// Итог считаем на клиенте только для показа — окончательную сумму
  /// вернёт сервер вместе с себестоимостью и прибылью.
  String _total(List<ProductDto> products) {
    var sum = Money.parse('0');

    for (final entry in _lines.entries) {
      final product = products.where((p) => p.id == entry.key).firstOrNull;
      if (product == null) continue;

      sum += Money.parse(product.salePrice) * Money.parse('${entry.value}');
    }

    return sum.toString();
  }

  Future<void> _submit(List<ProductDto> products) async {
    if (_method.needsCashAccount && _accountId == null) {
      setState(() => _error = 'Выберите кассу');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final lines = [
      for (final entry in _lines.entries)
        if (products.where((p) => p.id == entry.key).firstOrNull
            case final ProductDto product)
          SaleLine(
            product: product,
            quantity: entry.value,
            unitPrice: product.salePrice,
          ),
    ];

    try {
      await ref
          .read(salesApiProvider)
          .create(
            lines: lines,
            paymentMethod: _method,
            cashAccountId: _accountId,
            key: _key,
          );

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
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

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.quantity,
    required this.onChanged,
  });

  final ProductDto product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Больше остатка продать нельзя — сервер откажет с INSUFFICIENT_STOCK,
    // и лучше не давать набрать заведомо неверное количество.
    final canAdd = quantity < product.stockQuantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name),
                  Text(
                    '${Money.format(product.salePrice)} · '
                    'остаток ${product.stockQuantity}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: product.stockQuantity == 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 28,
              child: Text('$quantity', textAlign: TextAlign.center),
            ),
            IconButton(
              onPressed: canAdd ? () => onChanged(quantity + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.busy,
    required this.enabled,
    required this.onSubmit,
  });

  final String total;
  final bool busy;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Итого', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    Money.format(total),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: busy || !enabled ? null : onSubmit,
              style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Продать'),
            ),
          ],
        ),
      ),
    );
  }
}
