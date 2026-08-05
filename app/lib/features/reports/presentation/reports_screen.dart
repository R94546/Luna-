import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/report_dto.dart';
import 'providers/reports_provider.dart';

/// Выгрузка отчётов.
///
/// Период выбирается кнопками, а не двумя календарями: в девяти случаях
/// из десяти нужен «этот месяц» или «прошлый», и заставлять ради этого
/// дважды листать календарь — лишняя работа.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportType _type = ReportType.finance;
  ReportFormat _format = ReportFormat.xlsx;
  late _Period _period = _Period.thisMonth();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportExportProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Отчёты')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Что выгрузить', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: RadioGroup<ReportType>(
              groupValue: _type,
              // RadioGroup нельзя выключить целиком, поэтому во время
              // выгрузки просто игнорируем выбор: сменить тип на полпути
              // значит получить файл, которого не просили.
              onChanged: (value) {
                if (state.isBusy || value == null) return;
                setState(() => _type = value);
              },
              child: Column(
                children: [
                  for (final type in ReportType.values) ...[
                    if (type != ReportType.values.first)
                      const Divider(height: 1),
                    RadioListTile<ReportType>(
                      value: type,
                      title: Text(type.label),
                      subtitle: Text(type.description),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Период', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in _Preset.values)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: _period.preset == preset,
                  onSelected: state.isBusy
                      ? null
                      : (_) => _choosePreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _period.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),
          Text('Формат', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ReportFormat>(
            segments: [
              for (final format in ReportFormat.values)
                ButtonSegment(value: format, label: Text(format.label)),
            ],
            selected: {_format},
            onSelectionChanged: state.isBusy
                ? null
                : (value) => setState(() => _format = value.first),
          ),
          const SizedBox(height: 8),
          Text(
            _format == ReportFormat.xlsx
                ? 'Суммы числами — можно фильтровать и считать своё'
                : 'Готов к печати: альбомный лист, таблицы с итогами',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: state.isBusy ? null : _export,
            icon: state.isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(switch (state.stage) {
              ReportStage.building => 'Формируется…',
              ReportStage.downloading => 'Скачивается…',
              _ => 'Выгрузить',
            }),
          ),
          if (state.stage == ReportStage.ready) ...[
            const SizedBox(height: 12),
            _Result(
              path: state.filePath!,
              onOpen: () => ref.read(reportExportProvider.notifier).open(),
            ),
          ],
          if (state.stage == ReportStage.failed) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.error ?? 'Не удалось выгрузить отчёт',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choosePreset(_Preset preset) async {
    if (preset != _Preset.custom) {
      setState(() => _period = _Period.of(preset));
      return;
    }

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
    );

    if (range == null) return;
    setState(() => _period = _Period.custom(range.start, range.end));
  }

  void _export() {
    ref
        .read(reportExportProvider.notifier)
        .run(type: _type, format: _format, from: _period.from, to: _period.to);
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.split(RegExp(r'[/\\]')).last;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          Icons.check_circle_outline,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Готово'),
        subtitle: Text(name),
        trailing: TextButton(onPressed: onOpen, child: const Text('Открыть')),
      ),
    );
  }
}

enum _Preset {
  thisMonth('Этот месяц'),
  lastMonth('Прошлый месяц'),
  quarter('90 дней'),
  custom('Свой период');

  const _Preset(this.label);

  final String label;
}

/// Границы периода. Даты включительные — так же, как на бэкенде.
class _Period {
  const _Period({required this.preset, required this.from, required this.to});

  final _Preset preset;
  final DateTime from;
  final DateTime to;

  factory _Period.thisMonth() => _Period.of(_Preset.thisMonth);

  factory _Period.custom(DateTime from, DateTime to) =>
      _Period(preset: _Preset.custom, from: from, to: to);

  factory _Period.of(_Preset preset) {
    final now = DateTime.now();

    return switch (preset) {
      _Preset.thisMonth => _Period(
        preset: preset,
        from: DateTime(now.year, now.month),
        to: now,
      ),
      // День «0» следующего месяца — это последний день текущего:
      // так не приходится помнить про 28, 30 и 31 число.
      _Preset.lastMonth => _Period(
        preset: preset,
        from: DateTime(now.year, now.month - 1),
        to: DateTime(now.year, now.month, 0),
      ),
      _Preset.quarter => _Period(
        preset: preset,
        from: now.subtract(const Duration(days: 90)),
        to: now,
      ),
      _Preset.custom => _Period(preset: preset, from: now, to: now),
    };
  }

  String get label => '${_day(from)} — ${_day(to)}';

  static String _day(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}
