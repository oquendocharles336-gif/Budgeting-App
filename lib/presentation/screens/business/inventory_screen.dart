import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../../domain/services/photo_service.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/pending_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/optimistic.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/status_badge.dart';

/// Search box shared by the business lists (debounced).
class BusinessSearchField extends StatefulWidget {
  const BusinessSearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<BusinessSearchField> createState() => _BusinessSearchFieldState();
}

class _BusinessSearchFieldState extends State<BusinessSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.onChanged(v.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    _debounce?.cancel();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
        ),
        onChanged: _changed,
      );
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryProvider(_search));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'inventory_fab',
        tooltip: 'Add inventory item',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryFormScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: BusinessSearchField(hint: 'Search ingredients', onChanged: (v) => setState(() => _search = v)),
          ),
          Expanded(
            child: AsyncView<List<InventoryItem>>(
              value: items,
              onRetry: () => ref.invalidate(inventoryProvider(_search)),
              loading: const SkeletonList(),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: _search.isEmpty ? 'No ingredients yet' : 'No match for "$_search"',
                    message: _search.isEmpty ? 'Add items like "Sugar 100 g" or "Eggs 10 pcs".' : null,
                  );
                }
                final low = list.where((i) => i.isLow).length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  children: [
                    if (low > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StatusBadge(
                          label: '$low item${low == 1 ? '' : 's'} low on stock',
                          tone: BadgeTone.warning,
                          icon: Icons.warning_amber_rounded,
                        ),
                      ),
                    Card(
                      child: Column(
                        children: [for (final (i, item) in list.indexed) CascadeIn(index: i, child: _ItemTile(item: item))],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item});
  final InventoryItem item;

  Future<void> _restock(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restock ${item.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: 'Add how much?', suffixText: item.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0 || !context.mounted) return;
    final service = ref.read(businessServiceProvider);
    final key = newOpKey('restock');
    OptimisticWrite.run(
      context,
      savedText: 'Added ${formatQuantity(amount)} ${item.unit} to ${item.name}',
      what: 'the restock',
      show: (c) {
        final pending = c.read(pendingInventoryProvider.notifier)..put(key, item.copyWith(quantity: item.quantity + amount));
        return () => pending.clear(key);
      },
      // Same key on "Try again": it can only be added once.
      write: () => service.restock(item.id!, amount, opKey: key),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final saving = isUnsaved(item.id);
    return ListTile(
      minTileHeight: 64,
      onTap: saving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InventoryFormScreen(existing: item))),
      leading: PhotoThumb(path: item.photoPath, label: item.name, fallbackIcon: Icons.inventory_2_outlined),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(item.quantityLabel, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (item.isLow) const StatusBadge(label: 'Low stock', tone: BadgeTone.warning, icon: Icons.warning_amber_rounded),
          if (saving) const StatusBadge(label: 'Saving…', icon: Icons.sync_rounded),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Stock history of ${item.name}',
            onPressed: saving
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockHistoryScreen(item: item))),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Restock ${item.name}',
            onPressed: saving ? null : () => _restock(context, ref),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
    );
  }
}

/// Every stock change for one item: restocks, orders, adjustments and
/// stock returned from cancelled or edited orders. The stock shown is the
/// sum of these rows.
class StockHistoryScreen extends ConsumerWidget {
  const StockHistoryScreen({super.key, required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(stockHistoryProvider(item.id!));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Stock history · ${item.name}')),
      body: CascadeScope(
        child: AsyncView<List<StockMovement>>(
          value: history,
          onRetry: () => ref.invalidate(stockHistoryProvider(item.id!)),
          loading: const SkeletonList(),
          data: (rows) {
            if (rows.isEmpty) {
              return const EmptyState(icon: Icons.history_rounded, title: 'No stock changes yet');
            }
            final total = rows.fold<double>(0, (a, r) => a + r.change);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Semantics(
                  container: true,
                  child: AppCard(
                    child: Row(
                      children: [
                        Expanded(child: Text('In stock now', style: Theme.of(context).textTheme.titleMedium)),
                        Text('${formatQuantity(total < 0 ? 0 : total)} ${item.unit}', style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final (i, r) in rows.indexed)
                        CascadeIn(
                          index: i,
                          child: ListTile(
                            leading: ExcludeSemantics(
                              child: Icon(r.change >= 0 ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded),
                            ),
                            title: Text(r.reason.label + (r.orderId == null ? '' : ' #${r.orderId}')),
                            subtitle: Text(
                              [DateFormat('MMM d, yyyy h:mm a').format(r.date), ?r.note].join(' · '),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            trailing: Text(
                              '${r.change >= 0 ? '+' : '−'}${formatQuantity(r.change.abs())} ${item.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class InventoryFormScreen extends ConsumerStatefulWidget {
  const InventoryFormScreen({super.key, this.existing, this.recovered});
  final InventoryItem? existing;

  /// Put back after Android closed the app while the camera was open.
  final RecoveredForm? recovered;

  @override
  ConsumerState<InventoryFormScreen> createState() => _InventoryFormScreenState();
}

class _InventoryFormScreenState extends ConsumerState<InventoryFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _customUnit;
  late final TextEditingController _lowStock;
  late String _unit;
  late bool _custom;
  String? _photo;
  final _picked = PickedPhotos();
  late final PhotoService _photos;
  String? _savedPhoto;
  bool _saving = false;
  final _opKey = newOpKey('inventory');

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _photos = ref.read(photoServiceProvider);
    _name = TextEditingController(text: e?.name ?? '');
    _quantity = TextEditingController(text: e == null ? '' : formatQuantity(e.quantity));
    _lowStock = TextEditingController(text: e?.lowStock == null ? '' : formatQuantity(e!.lowStock!));
    _unit = e?.unit ?? 'pcs';
    _custom = !inventoryUnits.contains(_unit);
    _customUnit = TextEditingController(text: _custom ? _unit : '');
    _photo = e?.photoPath;
    _savedPhoto = e?.photoPath;
    // Rebuilt after Android closed the app during the camera: put the typed
    // values and the recovered photo back.
    final r = widget.recovered ?? _photos.takeRecovery(PhotoDraft.inventoryForm, e?.id);
    if (r != null) _restore(r);
  }

  void _restore(RecoveredForm r) {
    final f = r.draft.fields;
    _name.text = f['name'] ?? _name.text;
    _quantity.text = f['quantity'] ?? _quantity.text;
    _lowStock.text = f['lowStock'] ?? _lowStock.text;
    final unit = f['unit'];
    if (unit != null && unit.isNotEmpty) {
      _unit = unit;
      _custom = !inventoryUnits.contains(unit);
      if (_custom) _customUnit.text = unit;
    }
    _photo = r.photoPath ?? r.draft.photoPath ?? _photo;
    if (r.photoPath != null) _picked.add(r.photoPath);
    final message = r.message;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSnack(context, message);
      });
    }
  }

  PhotoDraft _draft() => PhotoDraft(
        form: PhotoDraft.inventoryForm,
        recordId: widget.existing?.id,
        photoPath: _photo,
        fields: {
          'name': _name.text,
          'quantity': _quantity.text,
          'lowStock': _lowStock.text,
          'unit': _custom ? _customUnit.text.trim() : _unit,
        },
      );

  @override
  void dispose() {
    // Photos picked but not saved are deleted; the camera draft is done.
    _picked.discardExcept(_photos, _savedPhoto);
    _photos.clearDraft();
    _name.dispose();
    _quantity.dispose();
    _customUnit.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  String? _validateNumber(String? v, {bool mandatory = true}) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return mandatory ? 'Enter a number' : null;
    final n = double.tryParse(t);
    if (n == null) return 'Enter a number, e.g. 2.5';
    if (n < 0) return 'Can\'t be negative';
    return null;
  }

  void _save() {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final e = widget.existing;
    final unit = _custom ? _customUnit.text.trim() : _unit;
    final low = _lowStock.text.trim();
    final item = InventoryItem(
      id: e?.id,
      name: _name.text.trim(),
      quantity: double.parse(_quantity.text.trim()),
      unit: unit,
      lowStock: low.isEmpty ? null : double.parse(low),
      photoPath: _photo,
      createdAt: e?.createdAt ?? now,
      updatedAt: now,
    );
    // The photo is kept even if the write fails: "Try again" saves it.
    _savedPhoto = _photo;
    final service = ref.read(businessServiceProvider);
    final key = _opKey;
    final preview = e == null
        ? InventoryItem(
            id: tempId(),
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            lowStock: item.lowStock,
            photoPath: item.photoPath,
            createdAt: now,
            updatedAt: now,
          )
        : item;
    OptimisticWrite.run(
      context,
      savedText: e == null ? 'Saved' : 'Changes saved',
      what: '"${item.name}"',
      show: (c) {
        final pending = c.read(pendingInventoryProvider.notifier)..put(key, preview);
        return () => pending.clear(key);
      },
      write: () => service.saveItem(item, previousPhoto: e?.photoPath, opKey: key),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${widget.existing!.name}?',
      message: 'Its stock history, its use in recipes and its photo are deleted too.',
    );
    if (!ok) return;
    try {
      await ref.read(businessServiceProvider).deleteItem(widget.existing!);
      _savedPhoto = null;
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete: $e', error: true);
      return;
    }
    ref.refreshData();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final unitLabel = _custom ? (_customUnit.text.trim().isEmpty ? null : _customUnit.text.trim()) : _unit;
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit item' : 'Add item'),
        actions: [
          if (isEdit) IconButton(tooltip: 'Delete item', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: Form(
        key: _form,
        child: FocusTraversalGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              PhotoField(
                path: _photo,
                label: _name.text,
                draft: _draft,
                onChanged: (p) => setState(() {
                  _picked.add(p);
                  _photo = p;
                }),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                autofocus: !isEdit && widget.recovered == null,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Sugar', counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantity,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numbers,
                decoration: InputDecoration(
                  labelText: isEdit ? 'Quantity in stock' : 'Starting quantity',
                  suffixText: unitLabel,
                  helperText: isEdit ? 'A change here is saved as an adjustment in the stock history.' : null,
                  helperMaxLines: 2,
                ),
                validator: _validateNumber,
              ),
              const SizedBox(height: 16),
              Text('Unit', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in inventoryUnits)
                    ChoiceChip(
                      label: Text(u),
                      selected: !_custom && _unit == u,
                      onSelected: (_) => setState(() {
                        _custom = false;
                        _unit = u;
                      }),
                    ),
                  ChoiceChip(label: const Text('Custom'), selected: _custom, onSelected: (_) => setState(() => _custom = true)),
                ],
              ),
              if (_custom) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customUnit,
                  maxLength: 12,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Your unit', hintText: 'e.g. tray, pack, cup', counterText: ''),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Type the unit' : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _lowStock,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numbers,
                decoration: InputDecoration(
                  labelText: 'Low-stock warning at (optional)',
                  suffixText: unitLabel,
                  helperText: 'Shows "Low stock" when the quantity is at or below this.',
                  helperMaxLines: 2,
                ),
                validator: (v) => _validateNumber(v, mandatory: false),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(isEdit ? 'Save changes' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
