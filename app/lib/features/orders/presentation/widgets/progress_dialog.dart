import 'package:flutter/material.dart';

import '../../data/order_dto.dart';
import '../../../../l10n/app_localizations.dart';

/// Отметка о произведённом по позициям заказа.
///
/// Ставится вручную: у выработки в схеме нет ссылки на заказ, и связать
/// «сшили 18 пар Спорт-12» с конкретным заказом, когда их два на одну
/// модель, не по чему.
class ProgressDialog extends StatefulWidget {
  const ProgressDialog({required this.order, super.key});

  final OrderDto order;

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final item in widget.order.items)
      item.id: TextEditingController(text: '${item.producedQuantity}'),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return AlertDialog(
      title: Text(l.ordersProduced),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in widget.order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[item.id],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: item.product.name,
                    // Заказано показываем подсказкой: без неё непонятно,
                    // сколько ещё осталось сделать.
                    helperText: l.ordersOrdered(item.quantity),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            for (final entry in _controllers.entries)
              entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
          }),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(l.actionSave),
        ),
      ],
    );
  }
}
