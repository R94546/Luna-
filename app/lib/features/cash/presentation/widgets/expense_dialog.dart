import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/idempotency.dart';
import '../../../../core/format/money.dart';
import '../../data/cash_dto.dart';
import '../providers/cash_provider.dart';

/// Новый расход.
///
/// Категории «Зарплата» в списке нет и быть не может: зарплата попадает
/// в кассу только через выплату, вместе с записью в ведомость. Появись
/// она здесь — те же деньги посчитались бы дважды.
class ExpenseDialog extends ConsumerStatefulWidget {
  const ExpenseDialog({super.key});

  @override
  ConsumerState<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<ExpenseDialog> {
  final _key = IdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  String? _categoryId;
  String? _accountId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final categoryId = _categoryId;
    final accountId = _accountId;
    final amount = _amount.text.trim();

    if (categoryId == null || accountId == null || amount.isEmpty) {
      setState(() => _error = 'Заполните сумму, категорию и кассу');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final now = DateTime.now();

      await ref
          .read(cashApiProvider)
          .createExpense(
            categoryId: categoryId,
            amount: amount,
            spentAt:
                '${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}',
            cashAccountId: accountId,
            note: _note.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);
    final accounts = ref.watch(cashAccountsProvider);

    return AlertDialog(
      title: const Text('Расход'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Сумма'),
            ),
            const SizedBox(height: 12),
            categories.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: [
                  for (final category in list)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _categoryId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Не удалось загрузить категории'),
            ),
            const SizedBox(height: 12),
            accounts.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _accountId ?? _pickDefault(list),
                decoration: const InputDecoration(labelText: 'Из кассы'),
                items: [
                  for (final account in list)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.name} · ${Money.compact(account.balance)}',
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _accountId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Не удалось загрузить кассы'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Комментарий'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Записать'),
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
