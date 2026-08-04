import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/idempotency.dart';
import '../../../../core/format/money.dart';
import '../../data/cash_dto.dart';
import '../providers/cash_provider.dart';

/// Ручная операция по кассе: внесение или изъятие владельцем.
///
/// Категорий продажи, зарплаты и расхода здесь нет: у каждой свой путь,
/// который заводит первичный документ вместе с движением. Сервер их тоже
/// не примет — здесь просто нечего выбрать.
class ManualTransactionDialog extends ConsumerStatefulWidget {
  const ManualTransactionDialog({super.key});

  @override
  ConsumerState<ManualTransactionDialog> createState() =>
      _ManualTransactionDialogState();
}

class _ManualTransactionDialogState
    extends ConsumerState<ManualTransactionDialog> {
  final _key = IdempotencyKey();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  ManualCategory _category = ManualCategory.investment;
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
    final accountId = _accountId;
    final amount = _amount.text.trim();

    if (accountId == null || amount.isEmpty) {
      setState(() => _error = 'Укажите сумму и кассу');
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
          .createTransaction(
            accountId: accountId,
            category: _category,
            amount: amount,
            occurredAt:
                '${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}',
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
    final accounts = ref.watch(cashAccountsProvider);

    return AlertDialog(
      title: const Text('Операция по кассе'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ManualCategory>(
              segments: [
                for (final category in ManualCategory.values)
                  ButtonSegment(value: category, label: Text(category.label)),
              ],
              selected: {_category},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _category = value.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Сумма'),
            ),
            const SizedBox(height: 12),
            accounts.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _accountId ?? _pickDefault(list),
                decoration: const InputDecoration(labelText: 'Касса'),
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
