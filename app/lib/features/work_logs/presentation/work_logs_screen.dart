import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/providers/session_provider.dart';
import '../data/work_log_dto.dart';
import 'providers/work_logs_provider.dart';
import 'widgets/work_log_tile.dart';

class WorkLogsScreen extends ConsumerStatefulWidget {
  const WorkLogsScreen({super.key});

  @override
  ConsumerState<WorkLogsScreen> createState() => _WorkLogsScreenState();
}

class _WorkLogsScreenState extends ConsumerState<WorkLogsScreen> {
  final _scroll = ScrollController();

  /// Выбранные для подтверждения пачкой. Пустое множество = обычный режим.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Подгружаем заранее, а не у самого дна: иначе на быстрой прокрутке
    // человек упирается в пустоту и думает, что список кончился.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(workLogsControllerProvider.notifier).loadMore();
    }
  }

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _approve(String id) => _runGuarded(
    () => ref.read(workLogsControllerProvider.notifier).approve(id),
  );

  Future<void> _reject(WorkLogDto log) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );

    // null — диалог закрыли, отклонять не просили.
    if (reason == null) return;

    await _runGuarded(
      () =>
          ref.read(workLogsControllerProvider.notifier).reject(log.id, reason),
    );
  }

  Future<void> _bulkApprove() async {
    final ids = _selected.toList();

    await _runGuarded(() async {
      final result = await ref
          .read(workLogsControllerProvider.notifier)
          .bulkApprove(ids);

      if (!mounted) return;
      setState(_selected.clear);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.skipped == 0
                ? 'Принято записей: ${result.approved}'
                : 'Принято ${result.approved}, пропущено ${result.skipped} — '
                      'их уже обработали',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(workLogsControllerProvider);
    final filter = ref.watch(workLogFilterControllerProvider);
    final role = ref.watch(sessionControllerProvider).value?.role;

    // Подтверждать может владелец и мастер. Бухгалтер выработку видит,
    // но не решает — на бэкенде эти эндпоинты ему закрыты.
    final canApprove = role?.canApproveWorkLogs ?? false;

    return Scaffold(
      appBar: AppBar(
        title: _selecting
            ? Text('Выбрано: ${_selected.length}')
            : const Text('Выработка'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        actions: [
          if (_selecting)
            TextButton(
              onPressed: _bulkApprove,
              child: const Text('Принять всё'),
            )
          // Для мастера и бухгалтера это единственный экран: без выхода
          // отсюда они заперты в приложении под чужой учёткой.
          else if (!(role?.canSeeDashboard ?? false))
            IconButton(
              tooltip: 'Выйти',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).logout(),
            ),
        ],
      ),
      body: Column(
        children: [
          _StatusFilter(
            value: filter.status,
            onChanged: (status) {
              setState(_selected.clear);
              ref
                  .read(workLogFilterControllerProvider.notifier)
                  .setStatus(status);
            },
          ),
          Expanded(
            child: AsyncValueBuilder(
              value: data,
              onRetry: () => ref.invalidate(workLogsControllerProvider),
              builder: (page) {
                if (page.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Записей нет',
                    message:
                        'Рабочие отчитываются через Telegram-бота — '
                        'отчёты появятся здесь',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(workLogsControllerProvider),
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: page.items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == page.items.length) {
                        return _Footer(
                          summary: page.summary,
                          loadingMore: ref
                              .read(workLogsControllerProvider.notifier)
                              .hasMore,
                        );
                      }

                      final log = page.items[index];

                      return WorkLogTile(
                        log: log,
                        selectable: _selecting,
                        selected: _selected.contains(log.id),
                        onTap: _selecting ? () => _toggle(log.id) : null,
                        // Длинное нажатие включает выбор пачкой — только
                        // на тех записях, которые вообще можно подтвердить.
                        onLongPress:
                            canApprove && log.status == WorkLogStatus.pending
                            ? () => _toggle(log.id)
                            : null,
                        onApprove: canApprove ? () => _approve(log.id) : null,
                        onReject: canApprove ? () => _reject(log) : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.value, required this.onChanged});

  final WorkLogStatus? value;
  final ValueChanged<WorkLogStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          for (final status in [
            WorkLogStatus.pending,
            WorkLogStatus.approved,
            WorkLogStatus.rejected,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(status.label),
                selected: value == status,
                onSelected: (_) => onChanged(status),
              ),
            ),
          ChoiceChip(
            label: const Text('Все'),
            selected: value == null,
            onSelected: (_) => onChanged(null),
          ),
        ],
      ),
    );
  }
}

/// Итоги под списком.
///
/// Считаются сервером по всей выборке с учётом фильтров, а не по
/// загруженным страницам: мастеру нужна сумма за день целиком.
class _Footer extends StatelessWidget {
  const _Footer({required this.summary, required this.loadingMore});

  final WorkLogSummaryDto summary;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Всего по фильтру',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.totalQuantity} пар',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  Money.format(summary.totalAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Отклонить запись'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLength: 255,
        decoration: const InputDecoration(
          labelText: 'Причина',
          hintText: 'Например: посчитано дважды',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          // Пустая строка, а не null: null означает «передумал»,
          // и без причины отклонить всё равно можно.
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}
