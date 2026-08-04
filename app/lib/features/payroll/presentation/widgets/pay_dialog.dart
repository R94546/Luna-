import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/idempotency.dart';
import '../../../../core/format/money.dart';
import '../../../cash/data/cash_dto.dart';
import '../../../cash/presentation/providers/cash_provider.dart';
import '../../data/payroll_dto.dart';
import '../providers/payroll_provider.dart';

/// Выплата сотруднику.
///
/// Ключ идемпотентности создаётся один раз на открытие диалога и живёт до
/// его закрытия: если связь оборвалась и человек жмёт «Выплатить» снова,
/// повтор уходит с тем же ключом, и сервер вернёт первый результат вместо
/// второй выплаты. Новый ключ появляется только у новой попытки.
class PayDialog extends ConsumerStatefulWidget {
  const PayDialog({required this.entry, required this.periodId, super.key});

  final PayrollEntryDto entry;
  final String periodId;

  @override
  ConsumerState<PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<PayDialog> {
  final _key = IdempotencyKey();
  late final _amount = TextEditingController(text: _suggested);
  final _note = TextEditingController();

  SalaryPaymentType _type = SalaryPaymentType.salary;
  String? _accountId;
  bool _busy = false;
  String? _error;

  /// Подставляем то, что причитается: чаще всего платят ровно эту сумму.
  String get _suggested {
    final toPay = Money.parse(widget.entry.toPay);
    return toPay.sign > 0 ? toPay.round().toString() : '';
  }

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
          .read(payrollApiProvider)
          .pay(
            employeeId: widget.entry.employee.id,
            type: _type,
            amount: amount,
            paidAt:
                '${now.year.toString().padLeft(4, '0')}-'
                '${now.month.toString().padLeft(2, '0')}-'
                '${now.day.toString().padLeft(2, '0')}',
            cashAccountId: accountId,
            payrollEntryId: widget.entry.id,
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
      title: Text('Выплата · ${widget.entry.employee.fullName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<SalaryPaymentType>(
              segments: [
                for (final type in SalaryPaymentType.values)
                  ButtonSegment(value: type, label: Text(type.label)),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
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
                initialValue: _accountId ?? _defaultAccount(list),
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
              : const Text('Выплатить'),
        ),
      ],
    );
  }

  String? _defaultAccount(List<CashAccountDto> accounts) {
    if (accounts.isEmpty) return null;

    final preferred = accounts.firstWhere(
      (a) => a.isDefault,
      orElse: () => accounts.first,
    );

    // Запоминаем, чтобы выбор не сбрасывался на каждой перерисовке.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _accountId == null) {
        setState(() => _accountId = preferred.id);
      }
    });

    return preferred.id;
  }
}
