import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/async_value_builder.dart';
import '../../../core/widgets/empty_state.dart';
import '../../catalog/data/catalog_dto.dart';
import '../../catalog/presentation/providers/catalog_provider.dart';
import '../data/costing_dto.dart';
import 'providers/costing_provider.dart';
import 'widgets/cost_item_dialog.dart';
import 'widgets/material_dialog.dart';
import '../../../l10n/app_localizations.dart';

/// Себестоимость: во что обходится пара и какую цену просить.
///
/// Две вкладки: сам расчёт и справочник материалов, из которого он берёт
/// цены. Держать их порознь незачем — материал заводят ровно тогда, когда
/// он понадобился в расчёте.
class CostingScreen extends StatelessWidget {
  const CostingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.costingTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l.costingTabCalc),
              Tab(text: l.costingTabMaterials),
            ],
          ),
        ),
        body: const TabBarView(children: [_CalculatorTab(), _MaterialsTab()]),
      ),
    );
  }
}

// ── Калькулятор ────────────────────────────────────────────────────────────

class _CalculatorTab extends ConsumerStatefulWidget {
  const _CalculatorTab();

  @override
  ConsumerState<_CalculatorTab> createState() => _CalculatorTabState();
}

class _CalculatorTabState extends ConsumerState<_CalculatorTab> {
  final _items = <CostItemInput>[];
  final _overhead = TextEditingController(text: '0');

  ProductDto? _product;
  double _margin = 30;
  CalculationDto? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _overhead.dispose();
    super.dispose();
  }

  /// Пересчёт на сервере: цены материалов и расценки знает он.
  Future<void> _calculate() async {
    if (_items.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(costingApiProvider)
          .calculate(
            productId: _product?.id,
            items: _items,
            overheadCost: _overhead.text.trim().isEmpty
                ? '0'
                : _overhead.text.trim(),
            marginPercent: _margin,
          );

      setState(() {
        _result = result;
        _busy = false;
      });
    } on ApiException catch (error) {
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  /// Цена при другой марже считается здесь.
  ///
  /// Наценка — это умножение готовой себестоимости, и гонять запрос
  /// на каждое движение ползунка ради него незачем.
  String get _price {
    final result = _result;
    if (result == null) return '0';

    final total = Money.parse(result.totalCost);
    return (total * Money.parse((1 + _margin / 100).toStringAsFixed(4)))
        .toString();
  }

  String get _profit {
    final result = _result;
    if (result == null) return '0';

    return (Money.parse(_price) - Money.parse(result.totalCost)).toString();
  }

  Future<void> _addItem() async {
    final item = await showDialog<CostItemInput>(
      context: context,
      builder: (_) => const CostItemDialog(),
    );

    if (item == null) return;
    setState(() => _items.add(item));
    await _calculate();
  }

  Future<void> _save() async {
    final l = L.of(context);

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );

    if (name == null || name.isEmpty) return;

    try {
      final saved = await ref
          .read(costingApiProvider)
          .save(
            name: name,
            productId: _product?.id,
            items: _items,
            overheadCost: _overhead.text.trim().isEmpty
                ? '0'
                : _overhead.text.trim(),
            marginPercent: _margin,
          );

      ref.invalidate(savedCalculationsProvider);
      if (!mounted) return;

      // Применение — отдельный шаг: расчёт часто делают «на посмотреть»,
      // а себестоимость модели участвует в прибыли каждой продажи.
      final apply = _product == null
          ? false
          : await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(l.costingApplyQuestion),
                content: Text(
                  l.costingApplyHint(
                    _product!.name,
                    Money.format(_result?.totalCost),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(l.costingLater),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(l.costingApply),
                  ),
                ],
              ),
            );

      if (apply == true) {
        await ref.read(costingApiProvider).apply(saved.id);
        ref.invalidate(catalogProductsProvider);
        ref.invalidate(savedCalculationsProvider);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.costingSaved)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final products = ref.watch(catalogProductsProvider).value ?? const [];
    final theme = Theme.of(context);
    final result = _result;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DropdownButtonFormField<ProductDto?>(
          initialValue: _product,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l.rateProduct,
            helperText: l.costingProductHint,
          ),
          items: [
            DropdownMenuItem(value: null, child: Text(l.costingNoProduct)),
            for (final product in products)
              DropdownMenuItem(
                value: product,
                child: Text(product.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            setState(() => _product = value);
            _calculate();
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(l.costingMaterials, style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.costingAdd),
            ),
          ],
        ),
        if (_items.isEmpty)
          Text(
            l.costingEmptyItems,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++)
                  _ItemRow(
                    item: _items[i],
                    breakdown: result != null && i < result.items.length
                        ? result.items[i]
                        : null,
                    onRemove: () {
                      setState(() => _items.removeAt(i));
                      _calculate();
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        TextField(
          controller: _overhead,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l.costingOverhead,
            helperText: l.costingOverheadHint,
          ),
          onSubmitted: (_) => _calculate(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(l.costingMargin, style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '${_margin.round()}%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: _margin,
          max: 200,
          divisions: 40,
          label: '${_margin.round()}%',
          onChanged: (value) => setState(() => _margin = value),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        if (result != null) ...[
          _Result(result: result, price: _price, profit: _profit),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(l.costingSave),
          ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.breakdown,
    required this.onRemove,
  });

  final CostItemInput item;
  final CostBreakdownDto? breakdown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Пока сервер не ответил, названия материала из справочника у нас нет —
    // показываем то, что известно, а не пустую строку.
    final name = breakdown?.name ?? item.name ?? L.of(context).materialTitle;
    final unit = breakdown?.unit ?? item.unit ?? '';

    return ListTile(
      dense: true,
      title: Text(name),
      subtitle: Text(
        '${item.quantity.toString().replaceAll(RegExp(r'\.0$'), '')} $unit'
        '${breakdown == null ? '' : ' × ${Money.format(breakdown!.unitPrice, withCurrency: false)}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (breakdown != null)
            Text(
              Money.format(breakdown!.total, withCurrency: false),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: L.of(context).actionRemove,
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.result,
    required this.price,
    required this.profit,
  });

  final CalculationDto result;
  final String price;
  final String profit;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Line(label: l.costingMaterials, value: result.materialsCost),
            _Line(
              label: l.costingWork,
              value: result.laborCost,
              // Разбивка объясняет, откуда взялась цифра: она сложена
              // из расценок, а не введена руками.
              hint: result.laborBreakdown.isEmpty
                  ? l.costingNoRates
                  : result.laborBreakdown.map((e) => e.operation).join(' · '),
            ),
            _Line(label: l.costingOverhead, value: result.overheadCost),
            const Divider(height: 20),
            _Line(label: l.costingTotal, value: result.totalCost, bold: true),
            const SizedBox(height: 8),
            _Line(
              label: l.costingPriceWithMargin,
              value: price,
              bold: true,
              color: theme.colorScheme.primary,
            ),
            _Line(label: l.costingProfitPerPair, value: profit),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.hint,
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final String? hint;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(Money.format(value), style: style),
            ],
          ),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.of(context).costingNameTitle),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(hintText: L.of(context).costingNameHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.of(context).actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text.trim()),
          child: Text(L.of(context).actionSave),
        ),
      ],
    );
  }
}

// ── Материалы ──────────────────────────────────────────────────────────────

class _MaterialsTab extends ConsumerWidget {
  const _MaterialsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);

    final materials = ref.watch(materialsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueBuilder(
        value: materials,
        onRetry: () => ref.invalidate(materialsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              title: l.costingMaterialsEmptyTitle,
              message: l.costingMaterialsEmptyHint,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final material = items[index];

              return ListTile(
                title: Text(material.name),
                subtitle: Text(l.materialPerUnit(material.unit)),
                trailing: Text(
                  Money.format(material.unitPrice),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => _edit(context, ref, material),
                onLongPress: () => _remove(context, ref, material),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    MaterialDto? material,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => MaterialDialog(material: material),
    );

    if (saved == true) ref.invalidate(materialsProvider);
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    MaterialDto material,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          L.of(dialogContext).costingMaterialRemoveTitle(material.name),
        ),
        content: Text(L.of(dialogContext).costingMaterialRemoveHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.of(context).actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.of(dialogContext).actionRemove),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(costingApiProvider).deleteMaterial(material.id);
      ref.invalidate(materialsProvider);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
