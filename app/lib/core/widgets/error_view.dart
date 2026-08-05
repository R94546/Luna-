import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_exception.dart';

/// Экран ошибки.
///
/// Текст берётся из ответа сервера — он уже переведён и говорит по делу
/// («На складе только 5 пар»), в отличие от «Произошла ошибка».
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final isNetwork = api?.isNetwork ?? false;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              api?.message ?? L.of(context).errorSomethingWrong,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(L.of(context).actionRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
