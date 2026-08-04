import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/catalog_api.dart';
import '../../data/catalog_dto.dart';

part 'catalog_provider.g.dart';

@riverpod
CatalogApi catalogApi(Ref ref) => CatalogApi(ref.watch(dioProvider));

/// Товары. keepAlive — их выбирают в продаже, заказе и расценке;
/// перезапрашивать справочник на каждое открытие формы незачем.
@Riverpod(keepAlive: true)
Future<List<ProductDto>> catalogProducts(Ref ref) =>
    ref.watch(catalogApiProvider).products();

@Riverpod(keepAlive: true)
Future<List<EmployeeDto>> catalogEmployees(Ref ref) =>
    ref.watch(catalogApiProvider).employees();

@Riverpod(keepAlive: true)
Future<List<OperationDto>> catalogOperations(Ref ref) =>
    ref.watch(catalogApiProvider).operations();

@riverpod
Future<List<PieceRateDto>> pieceRates(Ref ref) =>
    ref.watch(catalogApiProvider).pieceRates();

/// Обновляет справочники после правки.
///
/// Товары и операции связаны расценками: переименовал операцию — её имя
/// осталось в списке ставок. Дешевле перечитать три списка, чем объяснять,
/// почему в одном разделе новое название, а в соседнем старое.
void invalidateCatalog(WidgetRef ref) {
  ref
    ..invalidate(catalogProductsProvider)
    ..invalidate(catalogEmployeesProvider)
    ..invalidate(catalogOperationsProvider)
    ..invalidate(pieceRatesProvider);
}
