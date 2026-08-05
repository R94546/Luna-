import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/providers/session_provider.dart';

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _current.text;
    final next = _next.text;

    if (current.isEmpty || next.isEmpty) {
      setState(() => _error = L.of(context).passwordFillBoth);
      return;
    }

    // Совпадение проверяем здесь: гонять запрос ради опечатки в повторе
    // незачем, а сервер второго поля всё равно не видит.
    if (next != _repeat.text) {
      setState(() => _error = L.of(context).passwordMismatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(authApiProvider)
          .changePassword(currentPassword: current, newPassword: next);

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
      title: Text(l.settingsChangePassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _current,
              enabled: !_busy,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: l.passwordCurrent),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.passwordNew,
                helperText: l.passwordTooShort,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(labelText: l.passwordRepeat),
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
              : Text(l.actionChange),
        ),
      ],
    );
  }
}
