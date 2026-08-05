import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/costing_dto.dart';
import '../providers/costing_provider.dart';

/// Строка расхода: материал из справочника или разовый.
///
/// Разовый нужен затем, что мелочь под конкретную модель покупают один
/// раз, и заводить ради неё карточку в справочнике никто не станет —
/// а в себестоимость она входит.
class CostItemDialog extends ConsumerStatefulWidget {
  const CostItemDialog({super.key});

  @override
  ConsumerState<CostItemDialog> createState() => _CostItemDialogState();
}

class _CostItemDialogState extends ConsumerState<CostItemDialog> {
  MaterialDto? _material;
  bool _oneOff = false;

  final _quantity = TextEditingController(text: '1');
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = double.tryParse(
      _quantity.text.trim().replaceAll(',', '.'),
    );

    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Укажите количество');
      return;
    }

    if (_oneOff) {
      final name = _name.text.trim();
      final unit = _unit.text.trim();
      final price = _price.text.trim();

      if (name.isEmpty || unit.isEmpty || double.tryParse(price) == null) {
        setState(() => _error = 'Заполните название, единицу и цену');
        return;
      }

      Navigator.of(context).pop(
        CostItemInput(
          name: name,
          unit: unit,
          unitPrice: price,
          quantity: quantity,
        ),
      );
      return;
    }

    if (_material == null) {
      setState(() => _error = 'Выберите материал');
      return;
    }

    // Цена не передаётся намеренно: для материала из справочника её
    // подставит сервер, и она всегда актуальная.
    Navigator.of(
      context,
    ).pop(CostItemInput(materialId: _material!.id, quantity: quantity));
  }

  @override
  Widget build(BuildContext context) {
    final materials =
        ref.watch(materialsProvider).value ?? const <MaterialDto>[];

    return AlertDialog(
      title: const Text('Материал в расчёт'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Из справочника')),
                ButtonSegment(value: true, label: Text('Разовый')),
              ],
              selected: {_oneOff},
              onSelectionChanged: (value) =>
                  setState(() => _oneOff = value.first),
            ),
            const SizedBox(height: 16),
            if (_oneOff) ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(
                  labelText: 'Единица',
                  hintText: 'пара, кг, м',
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
            ] else if (materials.isEmpty)
              const Text(
                'Справочник материалов пуст — заполните вкладку «Материалы» '
                'или добавьте разовый материал',
              )
            else
              DropdownButtonFormField<MaterialDto>(
                initialValue: _material,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Материал'),
                items: [
                  for (final material in materials)
                    DropdownMenuItem(
                      value: material,
                      child: Text(
                        '${material.name} · ${material.unitPrice} за ${material.unit}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _material = value),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Количество',
                suffixText: _oneOff ? _unit.text.trim() : _material?.unit,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Добавить')),
      ],
    );
  }
}
