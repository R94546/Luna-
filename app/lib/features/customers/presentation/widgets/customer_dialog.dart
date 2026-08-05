import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/customer_dto.dart';
import '../providers/customers_provider.dart';
import '../../../../l10n/app_localizations.dart';

class CustomerDialog extends ConsumerStatefulWidget {
  const CustomerDialog({this.customer, super.key});

  final CustomerDto? customer;

  @override
  ConsumerState<CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends ConsumerState<CustomerDialog> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _note = TextEditingController(text: widget.customer?.note ?? '');

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();

    if (name.length < 2) {
      setState(() => _error = L.of(context).customersNameRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = ref.read(customersApiProvider);
      final customer = widget.customer;

      if (customer == null) {
        await api.create(
          name: name,
          phone: _phone.text.trim(),
          note: _note.text.trim(),
        );
      } else {
        await api.update(
          customer.id,
          name: name,
          phone: _phone.text.trim(),
          note: _note.text.trim(),
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
      title: Text(widget.customer == null ? l.customersNew : l.customersOne),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: widget.customer == null,
              decoration: InputDecoration(labelText: l.customersName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l.customersPhone),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 255,
              decoration: InputDecoration(labelText: l.customersNote),
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
              : Text(l.actionSave),
        ),
      ],
    );
  }
}
