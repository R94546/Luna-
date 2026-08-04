import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/customer_dto.dart';
import '../../data/customers_api.dart';

part 'customers_provider.g.dart';

@riverpod
CustomersApi customersApi(Ref ref) => CustomersApi(ref.watch(dioProvider));

/// Клиенты. keepAlive — их выбирают в заказе и продаже в долг.
@Riverpod(keepAlive: true)
Future<List<CustomerDto>> customers(Ref ref) =>
    ref.watch(customersApiProvider).list();

/// Карточка с долгом. Отдельным запросом: долг считается агрегатами
/// по продажам и заказам, и тянуть его для каждой строки списка значит
/// заставить сервер посчитать сотню сумм ради одной открытой карточки.
@riverpod
Future<CustomerDetailDto> customerDetail(Ref ref, String id) =>
    ref.watch(customersApiProvider).detail(id);
