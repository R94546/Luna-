import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/costing_dto.dart';
import '../providers/costing_provider.dart';

/// Материал: кожа, подошва, нитки, клей.
///
/// Единица измерения — свободный текст: цех меряет кожу в дм², подошву
/// в парах, клей в килограммах, и перечисление здесь однажды не даст
/// завести нужное.
class MaterialDialog extends ConsumerStatefulWidget {
  const MaterialDialog({this.material, super.key});

  final MaterialDto? material;

  @override
  ConsumerState<MaterialDialog> createState() => _MaterialDialogState();
}

class _MaterialDialogState extends ConsumerState<MaterialDialog> {
  late final _name = TextEditingController(text: widget.material?.name ?? '');
  late final _unit = TextEditingController(text: widget.material?.unit ?? '');
  late final _price = TextEditingController(
    text: widget.material?.unitPrice ?? '',
  );

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final price = _price.text.trim();

    if (name.length < 2) {
      setState(() => _error = 'Укажите название материала');
      return;
    }
    if (unit.isEmpty) {
      setState(() => _error = 'Укажите единицу измерения');
      return;
    }
    if (double.tryParse(price) == null) {
      setState(() => _error = 'Укажите цену за единицу');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(costingApiProvider);
      final material = widget.material;

      if (material == null) {
        await api.createMaterial(name: name, unit: unit, unitPrice: price);
      } else {
        await api.updateMaterial(
          material.id,
          name: name,
          unit: unit,
          unitPrice: price,
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
    return AlertDialog(
      title: Text(widget.material == null ? 'Новый материал' : 'Материал'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Единица',
                hintText: 'дм², пара, кг, м',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Цена за единицу'),
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
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
