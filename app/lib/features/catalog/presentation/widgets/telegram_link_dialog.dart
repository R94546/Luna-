import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../data/catalog_dto.dart';
import '../providers/catalog_provider.dart';

/// Код привязки рабочего к Telegram.
///
/// Показываем и ссылку, и код: ссылку удобно переслать, но чаще телефон
/// рабочего в руках у мастера — тогда шесть символов вводятся руками
/// быстрее, чем ищется чат для пересылки.
class TelegramLinkDialog extends ConsumerStatefulWidget {
  const TelegramLinkDialog({required this.employee, super.key});

  final EmployeeDto employee;

  @override
  ConsumerState<TelegramLinkDialog> createState() => _TelegramLinkDialogState();
}

class _TelegramLinkDialogState extends ConsumerState<TelegramLinkDialog> {
  late Future<TelegramLinkDto> _link;

  @override
  void initState() {
    super.initState();
    // Код заказываем сразу при открытии: диалог существует только ради него,
    // и лишняя кнопка «получить код» тут ничего не даёт.
    _link = ref.read(catalogApiProvider).createTelegramLink(widget.employee.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Подключить Telegram'),
      content: FutureBuilder<TelegramLinkDto>(
        future: _link,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final error = snapshot.error;
          if (error != null) {
            return Text(
              error is ApiException ? error.message : 'Не удалось получить код',
              style: TextStyle(color: theme.colorScheme.error),
            );
          }

          final link = snapshot.data!;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.employee.fullName, style: theme.textTheme.titleSmall),
              const SizedBox(height: 16),
              SelectableText(
                link.code,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Рабочий открывает бота и отправляет этот код. '
                'Код действует до ${_time(link.expiresAt)}.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _copy(link.deepLink),
                icon: const Icon(Icons.link),
                label: const Text('Скопировать ссылку'),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
