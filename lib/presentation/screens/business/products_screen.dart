import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money.dart';
import '../../../core/op_key.dart';
import '../../../data/models/business.dart';
import '../../../domain/services/app_lock_service.dart' show SessionTeardown;
import '../../../domain/services/photo_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/business_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/pending_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/skeleton.dart';
import '../../widgets/optimistic.dart';
import '../../widgets/photo_widgets.dart';
import '../../widgets/status_badge.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'products_fab',
        tooltip: 'Add product',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProductFormScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add product'),
      ),
      body: AsyncView<List<Product>>(
        value: products,
        onRetry: () => ref.invalidate(productsProvider),
        loading: const SkeletonList(),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.sell_rounded,
              title: 'No products yet',
              message: 'Add what you sell, with a price, a recipe and an optional photo.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Card(
                child: Column(
                  children: [
                    for (final (i, p) in list.indexed)
                      CascadeIn(
                        index: i,
                        child: ListTile(
                          minTileHeight: 64,
                          onTap: isUnsaved(p.id)
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductFormScreen(existing: p))),
                          leading: PhotoThumb(path: p.photoPath, label: p.name, fallbackIcon: Icons.sell_outlined),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: isUnsaved(p.id) ? const Align(alignment: Alignment.centerLeft, child: StatusBadge(label: 'Saving…', icon: Icons.sync_rounded)) : null,
                          trailing: AmountText(p.price, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing, this.recovered});
  final Product? existing;

  /// Put back after Android closed the app while the camera was open.
  final RecoveredForm? recovered;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  String? _photo;
  String? _savedPhoto;
  final _picked = PickedPhotos();

  /// For keeping the form when the app locks while it is open.
  late Map<String, String> _initialFields;
  String? _initialPhoto;
  bool _recovered = false;
  late final PhotoService _photos;
  final _opKey = newOpKey('product');

  /// Recipe: ingredients for ONE unit of the product. Null until loaded.
  List<RecipeLine>? _recipe;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _photos = ref.read(photoServiceProvider);
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: e == null ? '' : Money.toInput(e.price));
    _photo = e?.photoPath;
    _savedPhoto = e?.photoPath;
    if (e?.id == null) _recipe = [];
    // What the form starts with, to tell later whether anything was typed.
    _initialFields = _draft().fields;
    _initialPhoto = _photo;
    final r = widget.recovered ?? _photos.takeRecovery(PhotoDraft.productForm, e?.id);
    if (r != null) {
      _restore(r);
      _recovered = true;
    }
    if (_recipe == null) _loadRecipe(e!.id!);
  }

  Future<void> _loadRecipe(int id) async {
    try {
      final lines = await ref.read(businessServiceProvider).recipe(id);
      if (!mounted) return;
      setState(() {
        if (_recipe != null) return;
        _recipe = List.of(lines);
        // The saved recipe isn't a change the user made.
        if (!_recovered) _initialFields = _draft().fields;
      });
    } catch (_) {
      if (mounted) setState(() => _recipe ??= []);
    }
  }

  void _restore(RecoveredForm r) {
    final f = r.draft.fields;
    _name.text = f['name'] ?? _name.text;
    _price.text = f['price'] ?? _price.text;
    final recipe = f['recipe'];
    if (recipe != null) {
      try {
        final list = jsonDecode(recipe) as List;
        _recipe = [
          for (final m in list.cast<Map<String, dynamic>>())
            RecipeLine(
              itemId: m['itemId'] as int,
              quantity: (m['quantity'] as num).toDouble(),
              itemName: m['name'] as String?,
              unit: m['unit'] as String?,
            ),
        ];
      } catch (_) {
        // Keep the saved recipe.
      }
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
        form: PhotoDraft.productForm,
        recordId: widget.existing?.id,
        photoPath: _photo,
        fields: {
          'name': _name.text,
          'price': _price.text,
          if (_recipe != null)
            'recipe': jsonEncode([
              for (final l in _recipe!) {'itemId': l.itemId, 'quantity': l.quantity, 'name': l.itemName, 'unit': l.unit},
            ]),
        },
      );

  @override
  void dispose() {
    if (SessionTeardown.active) {
      // The app is locking, not the user cancelling: keep what was typed
      // and the picked photo, and reopen the form after unlocking.
      final d = _draft();
      if (_recovered || d.photoPath != _initialPhoto || !mapEquals(d.fields, _initialFields)) {
        SessionTeardown.track(_photos.keepDraftForUnlock(d));
      }
    } else {
      // Photos picked but not saved are deleted; the camera draft is done.
      _picked.discardExcept(_photos, _savedPhoto);
      _photos.clearDraft();
    }
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final items = await ref.read(inventoryRepositoryProvider).all();
    if (!mounted) return;
    final used = {for (final l in _recipe ?? const <RecipeLine>[]) l.itemId};
    final choices = items.where((i) => !used.contains(i.id)).toList();
    if (choices.isEmpty) {
      showSnack(context, items.isEmpty ? 'Add ingredients in the Inventory tab first.' : 'Every ingredient is already in the recipe.');
      return;
    }
    final item = await showModalBottomSheet<InventoryItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in choices)
                ListTile(
                  leading: PhotoThumb(path: i.photoPath, label: i.name, size: 40, fallbackIcon: Icons.inventory_2_outlined),
                  title: Text(i.name),
                  subtitle: Text('In stock: ${i.quantityLabel}'),
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (item == null || !mounted) return;
    final qty = await _askQuantity(item.name, item.unit);
    if (qty == null) return;
    setState(() => _recipe = [...?_recipe, RecipeLine(itemId: item.id!, quantity: qty, itemName: item.name, unit: item.unit)]);
  }

  Future<double?> _askQuantity(String name, String? unit, {double? initial}) async {
    final controller = TextEditingController(text: initial == null ? '' : formatQuantity(initial));
    final qty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name per 1 product'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: 'Amount used', suffixText: unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return qty;
  }

  void _save() {
    if (_saving || !_form.currentState!.validate()) return;
    if (_recipe == null) {
      showSnack(context, 'The recipe is still loading.');
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final e = widget.existing;
    final product = Product(
      id: e?.id,
      name: _name.text.trim(),
      price: Money.parse(_price.text)!.abs(),
      photoPath: _photo,
      createdAt: e?.createdAt ?? now,
      updatedAt: now,
    );
    final recipe = List<RecipeLine>.of(_recipe!);
    _savedPhoto = _photo;
    final service = ref.read(businessServiceProvider);
    final key = _opKey;
    final preview = e == null
        ? Product(id: tempId(), name: product.name, price: product.price, photoPath: product.photoPath, createdAt: now, updatedAt: now)
        : product;
    OptimisticWrite.run(
      context,
      savedText: e == null ? 'Saved' : 'Changes saved',
      what: '"${product.name}"',
      show: (c) {
        final pending = c.read(pendingProductsProvider.notifier)..put(key, preview);
        return () => pending.clear(key);
      },
      write: () => service.saveProduct(product, recipe: recipe, previousPhoto: e?.photoPath, opKey: key),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${widget.existing!.name}?',
      message: 'Past orders keep its name and price. Its recipe and photo are deleted.',
    );
    if (!ok) return;
    try {
      await ref.read(businessServiceProvider).deleteProduct(widget.existing!);
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
    final symbol = ref.watch(currencyProvider).symbol;
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    final recipe = _recipe;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit product' : 'Add product'),
        actions: [
          if (isEdit) IconButton(tooltip: 'Delete product', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
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
                decoration: const InputDecoration(labelText: 'Product name', hintText: 'e.g. Ube jam (250 g)', counterText: ''),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(labelText: 'Price', prefixText: '$symbol '),
                validator: (v) => validateAmount(v, allowZero: true),
              ),
              SectionHeader('Recipe (for 1 product)', actionLabel: 'Add ingredient', onAction: recipe == null ? null : _addIngredient),
              Text(
                'Each order uses these ingredients times its quantity, taken from stock when the order is created. '
                'No recipe = stock isn\'t changed.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (recipe == null)
                const SkeletonList(rows: 2, padding: EdgeInsets.zero)
              else if (recipe.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (final (i, line) in recipe.indexed)
                        ListTile(
                          title: Text(line.itemName ?? 'Ingredient'),
                          subtitle: Text('${formatQuantity(line.quantity)} ${line.unit ?? ''} per product'.trim()),
                          onTap: () async {
                            final q = await _askQuantity(line.itemName ?? 'Ingredient', line.unit, initial: line.quantity);
                            if (q != null) setState(() => recipe[i] = line.copyWith(quantity: q));
                          },
                          trailing: IconButton(
                            tooltip: 'Remove ${line.itemName ?? 'ingredient'} from the recipe',
                            onPressed: () => setState(() => recipe.removeAt(i)),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                    ],
                  ),
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
