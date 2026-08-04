import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../providers/catalog_provider.dart';

/// Новая сдельная расценка.
///
/// Модель и сотрудник необязательны, и это не мелочь интерфейса, а само
/// правило: пустое поле значит «для всех». Ставка на операцию действует
/// везде, пока для конкретной модели или человека не задана своя —
/// какая сработает, решает бэкенд в `piece-rates/resolve`.
///
/// Правка ставки не предусмотрена намеренно: цена работы, задним числом
/// изменённая, пересчитала бы уже выплаченную зарплату. Новая ставка
/// заводится поверх старой и действует с момента создания.
class PieceRateDialog extends ConsumerStatefulWidget {
  const PieceRateDialog({super.key});

  @override
  ConsumerState<PieceRateDialog> createState() => _PieceRateDialogState();
}

class _PieceRateDialogState extends ConsumerState<PieceRateDialog> {
  final _rate = TextEditingController();

  String? _operationId;
  String? _productId;
  String? _employeeId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final operationId = _operationId;
    final rate = _rate.text.trim().replaceAll(',', '.');

    if (operationId == null || rate.isEmpty) {
      setState(() => _error = 'Укажите операцию и ставку');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(catalogApiProvider)
          .createPieceRate(
            operationId: operationId,
            rate: rate,
            productId: _productId,
            employeeId: _employeeId,
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
    final operations = ref.watch(catalogOperationsProvider);
    final products = ref.watch(catalogProductsProvider);
    final employees = ref.watch(catalogEmployeesProvider);

    return AlertDialog(
      title: const Text('Расценка'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            operations.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _operationId,
                decoration: const InputDecoration(labelText: 'Операция'),
                items: [
                  for (final operation in list)
                    DropdownMenuItem(
                      value: operation.id,
                      child: Text(operation.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _operationId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Не удалось загрузить операции'),
            ),
            const SizedBox(height: 12),
            products.when(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'Модель'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Все модели'),
                  ),
                  for (final product in list)
                    DropdownMenuItem(
                      value: product.id,
                      child: Text('${product.sku} · ${product.name}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _productId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Не удалось загрузить модели'),
            ),
            const SizedBox(height: 12),
            employees.when(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: _employeeId,
                decoration: const InputDecoration(
                  labelText: 'Сотрудник',
                  helperText: 'Личная ставка перебивает общую',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все')),
                  for (final employee in list)
                    DropdownMenuItem(
                      value: employee.id,
                      child: Text(employee.fullName),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _employeeId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Не удалось загрузить сотрудников'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ставка за единицу'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
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
              : const Text('Добавить'),
        ),
      ],
    );
  }
}
