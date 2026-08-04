import 'package:dio/dio.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/idempotency.dart';
import 'cash_dto.dart';

class CashApi {
  const CashApi(this._dio);

  final Dio _dio;

  Future<List<CashAccountDto>> accounts() async {
    try {
      final response = await _dio.get<List<dynamic>>('/cash/accounts');

      return (response.data ?? [])
          .map((e) => CashAccountDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<CashJournalDto> journal() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/cash/transactions',
        queryParameters: {'limit': 50},
      );

      return CashJournalDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<CashSummaryDto> summary({
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/cash/summary',
        queryParameters: {'dateFrom': dateFrom, 'dateTo': dateTo},
      );

      return CashSummaryDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Ручная операция: владелец внёс свои деньги или забрал выручку.
  Future<void> createTransaction({
    required String accountId,
    required ManualCategory category,
    required String amount,
    required String occurredAt,
    required IdempotencyKey key,
    String? note,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/cash/transactions',
        data: {
          'accountId': accountId,
          'direction': category.direction.value,
          'category': category.value,
          'amount': amount,
          'occurredAt': occurredAt,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        options: key.options,
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  // ── Расходы ──────────────────────────────────────────────────────────────

  Future<List<ExpenseCategoryDto>> expenseCategories() async {
    try {
      final response = await _dio.get<List<dynamic>>('/expense-categories');

      return (response.data ?? [])
          .map((e) => ExpenseCategoryDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<ExpensesPageDto> expenses() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/expenses',
        queryParameters: {'limit': 50},
      );

      return ExpensesPageDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<void> createExpense({
    required String categoryId,
    required String amount,
    required String spentAt,
    required String cashAccountId,
    required IdempotencyKey key,
    String? note,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/expenses',
        data: {
          'categoryId': categoryId,
          'amount': amount,
          'spentAt': spentAt,
          'cashAccountId': cashAccountId,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        options: key.options,
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
