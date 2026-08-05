import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../providers/catalog_provider.dart';
import '../../../../l10n/app_localizations.dart';

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
      setState(() => _error = L.of(context).rateRequired);
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
    final l = L.of(context);

    final operations = ref.watch(catalogOperationsProvider);
    final products = ref.watch(catalogProductsProvider);
    final employees = ref.watch(catalogEmployeesProvider);

    return AlertDialog(
      title: Text(l.rateTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            operations.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _operationId,
                decoration: InputDecoration(labelText: l.rateOperation),
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
              error: (_, _) => Text(l.errorLoadOperations),
            ),
            const SizedBox(height: 12),
            products.when(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: _productId,
                decoration: InputDecoration(labelText: l.rateProduct),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l.catalogAllProducts),
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
              error: (_, _) => Text(l.errorLoadModels),
            ),
            const SizedBox(height: 12),
            employees.when(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: _employeeId,
                decoration: InputDecoration(
                  labelText: l.rateEmployee,
                  helperText: l.ratePersonalHint,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.workLogsAll)),
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
              error: (_, _) => Text(l.errorLoadEmployees),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.rateValue),
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
          child: Text(l.actionCancel),
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
              : Text(l.actionAdd),
        ),
      ],
    );
  }
}
