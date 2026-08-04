import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/order_dto.dart';
import '../../data/orders_api.dart';

part 'orders_provider.g.dart';

@riverpod
OrdersApi ordersApi(Ref ref) => OrdersApi(ref.watch(dioProvider));

/// Фильтр списка: null — все, кроме отдельной вкладки просроченных.
@riverpod
class OrdersFilter extends _$OrdersFilter {
  @override
  ({OrderStatus? status, bool overdue}) build() =>
      (status: null, overdue: false);

  void setStatus(OrderStatus? status) =>
      state = (status: status, overdue: false);

  void showOverdue() => state = (status: null, overdue: true);
}

@riverpod
Future<OrdersPageDto> orders(Ref ref) {
  final filter = ref.watch(ordersFilterProvider);

  return ref
      .watch(ordersApiProvider)
      .list(status: filter.status, overdue: filter.overdue);
}

/// Карточка заказа.
///
/// Действия возвращают заказ целиком: сервер сам пересчитывает прогресс,
/// долг и список доступных переходов, и брать его ответ надёжнее, чем
/// повторять автомат статусов на клиенте.
@riverpod
class OrderController extends _$OrderController {
  @override
  Future<OrderDto> build(String orderId) =>
      ref.watch(ordersApiProvider).byId(orderId);

  Future<void> changeStatus(
    OrderStatus status, {
    bool createSale = false,
    String? cashAccountId,
    String? paidAmount,
  }) async {
    state = await AsyncValue.guard(
      () => ref
          .read(ordersApiProvider)
          .changeStatus(
            orderId,
            status: status,
            createSale: createSale,
            cashAccountId: cashAccountId,
            paidAmount: paidAmount,
          ),
    );

    // Статус меняет и список: там он выводится вместе с признаком просрочки.
    ref.invalidate(ordersProvider);
  }

  Future<void> updateProgress(Map<String, int> producedByItem) async {
    state = await AsyncValue.guard(
      () => ref.read(ordersApiProvider).updateProgress(orderId, producedByItem),
    );

    ref.invalidate(ordersProvider);
  }
}
