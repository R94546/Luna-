import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Карточка рабочего.
///
/// «Основная операция» не обязательна, но экономит рабочему шаг в боте:
/// если специализация одна, бот не спрашивает, что именно тот сделал.
class EmployeeDialog extends ConsumerStatefulWidget {
  const EmployeeDialog({this.employee, super.key});

  final EmployeeDto? employee;

  @override
  ConsumerState<EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends ConsumerState<EmployeeDialog> {
  late final _fullName = TextEditingController(
    text: widget.employee?.fullName ?? '',
  );
  late final _phone = TextEditingController(text: widget.employee?.phone ?? '');
  late final _position = TextEditingController(
    text: widget.employee?.position ?? '',
  );

  late String? _operationId = widget.employee?.defaultOperation?.id;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _position.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fullName = _fullName.text.trim();

    if (fullName.length < 2) {
      setState(() => _error = L.of(context).employeeNameRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(catalogApiProvider);
      final employee = widget.employee;

      if (employee == null) {
        await api.createEmployee(
          fullName: fullName,
          phone: _phone.text.trim(),
          position: _position.text.trim(),
          defaultOperationId: _operationId,
        );
      } else {
        await api.updateEmployee(
          employee.id,
          fullName: fullName,
          phone: _phone.text.trim(),
          position: _position.text.trim(),
          defaultOperationId: _operationId,
        );
      }

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

    return AlertDialog(
      title: Text(widget.employee == null ? l.employeeNew : l.employeeOne),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _fullName,
              enabled: !_busy,
              autofocus: widget.employee == null,
              decoration: InputDecoration(labelText: l.employeeName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.employeePhone,
                hintText: '+998 90 123 45 67',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _position,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l.employeePosition),
            ),
            const SizedBox(height: 12),
            operations.when(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: _operationId,
                decoration: InputDecoration(
                  labelText: l.employeeDefaultOperation,
                  helperText: l.rateBotHint,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.catalogNotSet)),
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
              : Text(l.actionSave),
        ),
      ],
    );
  }
}
