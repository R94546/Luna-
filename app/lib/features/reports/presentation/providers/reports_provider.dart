import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/report_dto.dart';
import '../../data/reports_api.dart';

part 'reports_provider.g.dart';

@riverpod
ReportsApi reportsApi(Ref ref) => ReportsApi(ref.watch(dioProvider));

/// Что происходит с выгрузкой прямо сейчас.
enum ReportStage { idle, building, downloading, ready, failed }

class ReportState {
  const ReportState({this.stage = ReportStage.idle, this.filePath, this.error});

  final ReportStage stage;
  final String? filePath;
  final String? error;

  bool get isBusy =>
      stage == ReportStage.building || stage == ReportStage.downloading;
}

/// Выгрузка отчёта: постановка в очередь, ожидание, скачивание.
///
/// Сервер отвечает сразу, а файл собирает в фоне — поэтому здесь опрос.
/// Пользователю показывается одна кнопка и её состояние: собирать и качать
/// он не должен различать, для него это «формируется».
@riverpod
class ReportExport extends _$ReportExport {
  @override
  ReportState build() => const ReportState();

  Future<void> run({
    required L l10n,
    required ReportType type,
    required ReportFormat format,
    required DateTime from,
    required DateTime to,
  }) async {
    if (state.isBusy) return;

    state = const ReportState(stage: ReportStage.building);
    final api = ref.read(reportsApiProvider);

    try {
      final job = await api.export(
        type: type,
        format: format,
        from: from,
        to: to,
      );

      final ready = await _waitReady(api, job, l10n);
      if (ready == null) {
        state = ReportState(
          stage: ReportStage.failed,
          error: l10n.reportsTooLong,
        );
        return;
      }

      state = const ReportState(stage: ReportStage.downloading);

      // Файл живёт на сервере полчаса, поэтому кладём его себе: человек
      // открывает выгрузку и через день, уже без сети.
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}${Platform.pathSeparator}${ready.fileName}';

      await api.download(ready.jobId, path);

      // Файл не открывается сам: на телефоне это выкинуло бы человека
      // в Excel посреди работы, а на десктопе — запустило бы стороннее
      // приложение без спроса. Кнопка «Открыть» рядом.
      state = ReportState(stage: ReportStage.ready, filePath: path);
    } on ApiException catch (error) {
      state = ReportState(stage: ReportStage.failed, error: error.message);
    } catch (error) {
      // Сюда попадает всё платформенное: нет доступа к папке, нет места
      // на диске, в браузере вовсе нет файловой системы. Показать
      // техническую ошибку человеку нечестно — он с ней ничего не сделает.
      state = ReportState(
        stage: ReportStage.failed,
        error: l10n.reportsSaveFailed,
      );
    }
  }

  /// Открыть скачанный файл системным приложением.
  Future<void> open() async {
    final path = state.filePath;
    if (path != null) await OpenFilex.open(path);
  }

  void reset() => state = const ReportState();

  /// Опрос статуса. Полминуты хватает даже отчёту за год; дальше молчание
  /// сервера — это уже поломка, а не долгая работа.
  Future<ReportJobDto?> _waitReady(
    ReportsApi api,
    ReportJobDto job,
    L l10n,
  ) async {
    var current = job;

    for (var attempt = 0; attempt < 60; attempt++) {
      if (current.isReady) return current;
      if (current.isFailed) {
        throw ApiException(
          statusCode: 500,
          code: 'REPORT_FAILED',
          message: l10n.reportsBuildFailed,
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
      current = await api.status(current.jobId);
    }

    return null;
  }
}
