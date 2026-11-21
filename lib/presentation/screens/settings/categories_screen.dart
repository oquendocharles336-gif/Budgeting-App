import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/default_data.dart';
import '../../../data/models/category.dart';
import '../../../data/models/transaction_entry.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/category_icons.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: AsyncView<List<Category>>(
        value: cats,
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            for (final kind in const [TransactionKind.expense, TransactionKind.income]) ...[
              SectionHeader(kind == TransactionKind.expense ? 'Expense categories' : 'Income types'),
              Card(
                child: Column(
                  children: [
                    for (final c in list.where((c) => c.kind == kind))
                      ListTile(
                        leading: CategoryAvatar(category: c),
                        title: Text(c.name),
                        subtitle: c.isOther
                            ? const Text('You type the name each time')
                            : c.isLoan
                                ? const Text('Also adds a debt')
                                : c.isDefault
                                    ? const Text('Default')
                                    : null,
                        trailing: (c.id == DefaultData.other || c.role != null)
                            ? null
                            : IconButton(
                                tooltip: 'Delete ${c.name}',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () async {
                                  final ok = await confirm(
                                    context,
                                    title: 'Delete "${c.name}"?',
                                    message: c.isIncome
                                        ? 'Its transactions move to "Other income".'
                                        : 'Its transactions move to "Other". Its budgets and keyword rules are removed.',
                                  );
                                  if (!ok) return;
                                  await ref.read(categoryRepositoryProvider).delete(c.id!);
                                  ref.refreshData();
                                },
                              ),
                        onTap: () => showCategoryEditor(context, ref, existing: c),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showCategoryEditor(BuildContext context, WidgetRef ref, {Category? existing}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  var icon = existing?.icon ?? 'other';
  var color = Color(existing?.color ?? CategoryIcons.palette.first);
  var kind = existing?.kind ?? TransactionKind.expense;
  final formKey = GlobalKey<FormState>();
  final repo = ref.read(categoryRepositoryProvider);

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'New category' : 'Edit category', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name', counterText: ''),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                if (existing == null) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<TransactionKind>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: TransactionKind.expense, label: Text('Expense')),
                      ButtonSegment(value: TransactionKind.income, label: Text('Income')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => setState(() => kind = v.first),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Icon', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in CategoryIcons.all.entries)
                      Semantics(
                        button: true,
                        selected: e.key == icon,
                        label: e.key,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => icon = e.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: e.key == icon ? color.withValues(alpha: 0.2) : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: e.key == icon ? Border.all(color: color, width: 2) : null,
                            ),
                            child: Icon(e.value, color: e.key == icon ? color : null),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Color', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                ColorPickerField(
                  colors: [for (final c in CategoryIcons.palette) Color(c)],
                  selected: color,
                  onChanged: (c) => setState(() => color = c),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final n = name.text.trim();
                    if (await repo.nameExists(n, exceptId: existing?.id)) {
                      if (ctx.mounted) showSnack(ctx, 'A category called "$n" already exists', error: true);
                      return;
                    }
                    if (existing == null) {
                      await repo.insert(Category(name: n, icon: icon, color: color.toARGB32(), kind: kind));
                    } else {
                      await repo.update(existing.copyWith(name: n, icon: icon, color: color.toARGB32()));
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (saved == true) ref.refreshData();
}
