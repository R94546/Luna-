import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/payroll_api.dart';
import '../../data/payroll_dto.dart';

part 'payroll_provider.g.dart';

@riverpod
PayrollApi payrollApi(Ref ref) => PayrollApi(ref.watch(dioProvider));

@riverpod
Future<List<PeriodSummaryDto>> payrollPeriods(Ref ref) =>
    ref.watch(payrollApiProvider).periods();

/// Ведомость одного периода.
///
/// Действия возвращают обновлённый период целиком — сервер пересчитывает
/// начисления и итог, и брать его ответ надёжнее, чем править состояние
/// у себя и надеяться, что формулы совпали.
@riverpod
class PeriodController extends _$PeriodController {
  @override
  Future<PeriodDto> build(String periodId) =>
      ref.watch(payrollApiProvider).period(periodId);

  Future<void> calculate() => _apply((api) => api.calculate(periodId));

  Future<void> close() async {
    await _apply((api) => api.close(periodId));
    // Закрытый период меняет список: там свой статус и итог.
    ref.invalidate(payrollPeriodsProvider);
  }

  Future<void> updateEntry(
    String entryId, {
    String? bonus,
    String? deduction,
  }) => _apply(
    (api) => api.updateEntry(entryId, bonus: bonus, deduction: deduction),
  );

  /// Выплата меняет и ведомость, и кассу, поэтому период перечитывается,
  /// а не правится точечно: `advancePaid` и `toPay` считает сервер.
  Future<void> reload() async {
    state = await AsyncValue.guard(
      () => ref.read(payrollApiProvider).period(periodId),
    );
  }

  Future<void> _apply(Future<PeriodDto> Function(PayrollApi api) action) async {
    final api = ref.read(payrollApiProvider);
    state = await AsyncValue.guard(() => action(api));
  }
}

@riverpod
Future<SalaryPaymentsPageDto> salaryPayments(Ref ref) =>
    ref.watch(payrollApiProvider).payments();
