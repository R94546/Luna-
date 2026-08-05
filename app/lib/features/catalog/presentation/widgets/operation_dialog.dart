import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Вид работы: раскрой, затяжка, пошив.
///
/// Порядок задаётся числом, а не перетаскиванием списка: операции идут
/// по ходу производства, и рабочий в боте видит их в том же порядке,
/// в каком делает.
class OperationDialog extends ConsumerStatefulWidget {
  const OperationDialog({this.operation, super.key});

  final OperationDto? operation;

  @override
  ConsumerState<OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends ConsumerState<OperationDialog> {
  late final _name = TextEditingController(text: widget.operation?.name ?? '');
  late final _code = TextEditingController(text: widget.operation?.code ?? '');
  late final _sortOrder = TextEditingController(
    text: (widget.operation?.sortOrder ?? 0).toString(),
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();

    if (name.length < 2) {
      setState(() => _error = L.of(context).operationNameRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(catalogApiProvider);
      final operation = widget.operation;
      final sortOrder = int.tryParse(_sortOrder.text.trim()) ?? 0;

      if (operation == null) {
        await api.createOperation(
          name: name,
          code: _code.text.trim(),
          sortOrder: sortOrder,
        );
      } else {
        await api.updateOperation(
          operation.id,
          name: name,
          code: _code.text.trim(),
          sortOrder: sortOrder,
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

    return AlertDialog(
      title: Text(widget.operation == null ? l.operationNew : l.operationOne),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: widget.operation == null,
              decoration: InputDecoration(labelText: l.operationName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !_busy,
              decoration: InputDecoration(labelText: l.operationCode),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sortOrder,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.operationOrder,
                helperText: l.operationOrderHint,
              ),
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
