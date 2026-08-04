import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/sale_dto.dart';
import '../../data/sales_api.dart';

part 'sales_provider.g.dart';

@riverpod
SalesApi salesApi(Ref ref) => SalesApi(ref.watch(dioProvider));

@riverpod
Future<SalesPageDto> sales(Ref ref) => ref.watch(salesApiProvider).list();

/// Справочник товаров. keepAlive — он нужен на каждое открытие формы
/// продажи, и перезапрашивать его каждый раз незачем.
@Riverpod(keepAlive: true)
Future<List<ProductDto>> products(Ref ref) =>
    ref.watch(salesApiProvider).products();
