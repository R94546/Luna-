import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_view.dart';

/// Три состояния асинхронных данных в одном месте.
///
/// Без этого каждый экран пишет свои `loading` и `error`, и они расходятся:
/// на одном экране спиннер по центру, на другом сверху, на третьем ошибка
/// молча съедена. Здесь же — единственное место, где это решается.
class AsyncValueBuilder<T> extends StatelessWidget {
  const AsyncValueBuilder({
    required this.value,
    required this.builder,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, onRetry: onRetry),
      // Во время обновления показываем прежние данные, а не спиннер поверх
      // экрана: pull-to-refresh не должен стирать то, что человек читает.
      skipLoadingOnRefresh: true,
    );
  }
}
