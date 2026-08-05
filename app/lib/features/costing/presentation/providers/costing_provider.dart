import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/costing_api.dart';
import '../../data/costing_dto.dart';

part 'costing_provider.g.dart';

@riverpod
CostingApi costingApi(Ref ref) => CostingApi(ref.watch(dioProvider));

/// Справочник материалов. keepAlive — его открывают из калькулятора
/// на каждую добавленную строку.
@Riverpod(keepAlive: true)
Future<List<MaterialDto>> materials(Ref ref) =>
    ref.watch(costingApiProvider).materials();

@riverpod
Future<List<SavedCalculationDto>> savedCalculations(Ref ref) =>
    ref.watch(costingApiProvider).saved();
