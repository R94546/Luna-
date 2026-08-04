import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/cash_api.dart';
import '../../data/cash_dto.dart';

part 'cash_provider.g.dart';

@riverpod
CashApi cashApi(Ref ref) => CashApi(ref.watch(dioProvider));

/// Кассы. keepAlive — их выбирают в каждой денежной форме, и
/// перезапрашивать список на каждое открытие диалога незачем.
@Riverpod(keepAlive: true)
Future<List<CashAccountDto>> cashAccounts(Ref ref) =>
    ref.watch(cashApiProvider).accounts();

@riverpod
Future<CashJournalDto> cashJournal(Ref ref) =>
    ref.watch(cashApiProvider).journal();

@riverpod
Future<CashSummaryDto> cashSummary(Ref ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month);
  // Нулевой день следующего месяца — последний день текущего.
  final to = DateTime(now.year, now.month + 1, 0);

  return ref
      .watch(cashApiProvider)
      .summary(dateFrom: _date(from), dateTo: _date(to));
}

@riverpod
Future<List<ExpenseCategoryDto>> expenseCategories(Ref ref) =>
    ref.watch(cashApiProvider).expenseCategories();

@riverpod
Future<ExpensesPageDto> expenses(Ref ref) =>
    ref.watch(cashApiProvider).expenses();

/// Обновляет всё, на что влияет движение денег.
///
/// Одна операция меняет баланс кассы, журнал, сводку и список расходов —
/// перечитывать надо все четыре, иначе на соседней вкладке останется
/// цифра, которой уже нет.
///
/// Принимает WidgetRef: вызывается с экранов после выплаты или расхода.
void invalidateMoney(WidgetRef ref) {
  ref
    ..invalidate(cashAccountsProvider)
    ..invalidate(cashJournalProvider)
    ..invalidate(cashSummaryProvider)
    ..invalidate(expensesProvider);
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
