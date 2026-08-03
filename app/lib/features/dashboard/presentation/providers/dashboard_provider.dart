import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/dashboard_api.dart';
import '../../data/dashboard_dto.dart';

part 'dashboard_provider.g.dart';

@riverpod
DashboardApi dashboardApi(Ref ref) => DashboardApi(ref.watch(dioProvider));

/// Данные главного экрана.
///
/// Период — параметр провайдера: Riverpod держит отдельный кэш на каждое
/// значение, и возврат к уже просмотренному месяцу не заставит ждать
/// повторной загрузки.
@riverpod
Future<DashboardDto> dashboard(Ref ref, DashboardPeriod period) {
  return ref.watch(dashboardApiProvider).load(period);
}
