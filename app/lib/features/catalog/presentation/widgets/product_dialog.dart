import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';

/// Карточка модели обуви.
///
/// Начальный остаток спрашиваем только при создании: у существующего товара
/// склад двигается движениями, и правка остатка «в форме» разошлась бы
/// с журналом, по которому этот остаток сходится.
class ProductDialog extends ConsumerStatefulWidget {
  const ProductDialog({this.product, super.key});

  final ProductDto? product;

  @override
  ConsumerState<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<ProductDialog> {
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _category = TextEditingController(
    text: widget.product?.category ?? '',
  );
  late final _salePrice = TextEditingController(
    text: _initialMoney(widget.product?.salePrice),
  );
  late final _costPrice = TextEditingController(
    text: _initialMoney(widget.product?.costPrice),
  );
  late final _minStock = TextEditingController(
    text: (widget.product?.minStockLevel ?? 0).toString(),
  );
  final _initialStock = TextEditingController(text: '0');

  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _category.dispose();
    _salePrice.dispose();
    _costPrice.dispose();
    _minStock.dispose();
    _initialStock.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sku = _sku.text.trim();
    final name = _name.text.trim();

    if (sku.isEmpty || name.length < 2) {
      setState(() => _error = 'Укажите артикул и название');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(catalogApiProvider);
      final product = widget.product;

      if (product == null) {
        await api.createProduct(
          sku: sku,
          name: name,
          category: _category.text.trim(),
          salePrice: _money(_salePrice.text),
          costPrice: _money(_costPrice.text),
          minStockLevel: _int(_minStock.text),
          initialStock: _int(_initialStock.text),
        );
      } else {
        await api.updateProduct(
          product.id,
          sku: sku,
          name: name,
          category: _category.text.trim(),
          salePrice: _money(_salePrice.text),
          costPrice: _money(_costPrice.text),
          minStockLevel: _int(_minStock.text),
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
      title: Text(_isEdit ? 'Модель' : 'Новая модель'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _sku,
              enabled: !_busy,
              autofocus: !_isEdit,
              decoration: const InputDecoration(labelText: 'Артикул'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Категория'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salePrice,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Цена продажи'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costPrice,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Себестоимость',
                helperText: 'Из неё считается прибыль по продаже',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minStock,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Минимальный остаток',
                helperText: 'Ниже него модель попадёт в «заканчивается»',
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _initialStock,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Остаток на складе сейчас',
                ),
              ),
            ],
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
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  /// Пустое поле цены — это ноль, а не ошибка валидации.
  static String _money(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    return value.isEmpty ? '0' : value;
  }

  static int _int(String raw) => int.tryParse(raw.trim()) ?? 0;

  /// «12000.00» в поле ввода читается хуже, чем «12000».
  static String _initialMoney(String? value) {
    if (value == null) return '';
    return value.endsWith('.00') ? value.substring(0, value.length - 3) : value;
  }
}
