import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Движение склада руками: закупка, возврат, брак, инвентаризация.
///
/// Продажи и выдачи заказов сюда не попадают — их движения заводят сами
/// документы. Иначе один и тот же товар списался бы дважды: продажей
/// и «на всякий случай» руками.
class StockMovementDialog extends ConsumerStatefulWidget {
  const StockMovementDialog({required this.product, super.key});

  final ProductDto product;

  @override
  ConsumerState<StockMovementDialog> createState() =>
      _StockMovementDialogState();
}

class _StockMovementDialogState extends ConsumerState<StockMovementDialog> {
  final _quantity = TextEditingController();
  final _note = TextEditingController();

  MovementType _type = MovementType.purchaseIn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantity.text.trim());

    if (quantity == null || quantity < 0) {
      setState(() => _error = L.of(context).costingQuantityRequired);
      return;
    }

    // Ноль осмыслен только при инвентаризации: «пересчитали, ничего нет».
    // Для прихода и списания это пустая запись в журнале.
    if (quantity == 0 && !_type.isAbsolute) {
      setState(() => _error = L.of(context).stockQuantityPositive);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(catalogApiProvider)
          .createMovement(
            productId: widget.product.id,
            type: _type,
            quantity: quantity,
            note: _note.text.trim(),
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

    return AlertDialog(
      title: Text(l.stockMovement),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.stockCurrent(widget.product.name, widget.product.stockQuantity),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MovementType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: l.stockType),
              items: [
                for (final type in MovementType.values)
                  DropdownMenuItem(value: type, child: Text(type.label(l))),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _type.isAbsolute ? l.stockActual : l.quantity,
                helperText: _type.isAbsolute ? l.stockActualHint : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 255,
              decoration: InputDecoration(labelText: l.fieldComment),
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
              : Text(l.cashRecord),
        ),
      ],
    );
  }
}
