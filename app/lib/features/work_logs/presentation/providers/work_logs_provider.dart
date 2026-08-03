import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/work_log_dto.dart';
import '../../data/work_logs_api.dart';

part 'work_logs_provider.g.dart';

@riverpod
WorkLogsApi workLogsApi(Ref ref) => WorkLogsApi(ref.watch(dioProvider));

/// Текущий фильтр списка. Отдельным провайдером, чтобы смена фильтра
/// перезагружала список, а не наоборот.
@riverpod
class WorkLogFilterController extends _$WorkLogFilterController {
  @override
  WorkLogFilter build() => const WorkLogFilter();

  void setStatus(WorkLogStatus? status) {
    state = status == null
        ? state.copyWith(resetStatus: true)
        : state.copyWith(status: status);
  }

  void setEmployee(String? employeeId) {
    state = employeeId == null
        ? state.copyWith(resetEmployee: true)
        : state.copyWith(employeeId: employeeId);
  }

  void setDates(DateTime? from, DateTime? to) {
    state = from == null
        ? state.copyWith(resetDates: true)
        : state.copyWith(dateFrom: from, dateTo: to);
  }

  void clearExtras() {
    state = state.copyWith(resetEmployee: true, resetDates: true);
  }
}

/// Список выработки с подгрузкой страниц.
///
/// Страницы накапливаются в одном состоянии: отчётов за месяц набегает
/// несколько сотен, и грузить их разом — секунды ожидания на плохой связи.
@riverpod
class WorkLogsController extends _$WorkLogsController {
  int _page = 1;
  bool _loadingMore = false;

  @override
  Future<WorkLogPageDto> build() async {
    _page = 1;
    final filter = ref.watch(workLogFilterControllerProvider);

    return ref.watch(workLogsApiProvider).list(filter, page: 1);
  }

  bool get hasMore {
    final data = state.valueOrNull;
    return data != null && data.meta.page < data.meta.totalPages;
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || _loadingMore || !hasMore) return;

    _loadingMore = true;

    try {
      final filter = ref.read(workLogFilterControllerProvider);
      final next = await ref
          .read(workLogsApiProvider)
          .list(filter, page: _page + 1);

      _page += 1;

      // Итоги берём из свежего ответа: они считаются по всей выборке,
      // а не по загруженным страницам.
      state = AsyncData(
        next.copyWith(items: [...current.items, ...next.items]),
      );
    } on Object catch (error, stack) {
      state = AsyncError(error, stack);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> approve(String id) => _mutate(() async {
    await ref.read(workLogsApiProvider).approve(id);
  });

  Future<void> reject(String id, String? reason) => _mutate(() async {
    await ref.read(workLogsApiProvider).reject(id, reason);
  });

  Future<BulkApproveResultDto> bulkApprove(List<String> ids) async {
    final result = await ref.read(workLogsApiProvider).bulkApprove(ids);
    await _refresh();
    return result;
  }

  /// После любого изменения список перечитывается целиком.
  ///
  /// Подтверждённая запись уезжает из выборки «Ждут», меняются итоги
  /// и бейдж на главной — точечно подправить состояние значит рано или
  /// поздно разойтись с сервером.
  Future<void> _mutate(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  Future<void> _refresh() async {
    _page = 1;
    final filter = ref.read(workLogFilterControllerProvider);

    state = await AsyncValue.guard(
      () => ref.read(workLogsApiProvider).list(filter, page: 1),
    );
  }
}
