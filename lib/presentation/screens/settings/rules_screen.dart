import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category.dart';
import '../../../domain/import/auto_categorizer.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Keyword -> category rules used to auto-categorize new transactions.
class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  final _test = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _test.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final cats = ref.watch(categoryMapProvider).asDataOrNull ?? const <int, Category>{};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Auto-categorize rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null, cats.values.where((c) => !c.isIncome).toList()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New rule'),
      ),
      body: AsyncView<List<CategoryRule>>(
        value: rules,
        data: (list) {
          final tester = AutoCategorizer(list);
          final hit = _test.text.trim().isEmpty ? null : tester.match(_test.text);
          final filtered = _query.isEmpty
              ? list
              : list.where((r) => r.keyword.toLowerCase().contains(_query) || (cats[r.categoryId]?.name.toLowerCase().contains(_query) ?? false)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text(
                'When a description contains a keyword (at the start of a word), that category is picked. '
                'Longer keywords win, so "grabfood" beats "grab".',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _test,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Try a description', hintText: 'e.g. GRABFOOD MAKATI', prefixIcon: Icon(Icons.science_rounded)),
              ),
              if (_test.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    hit == null
                        ? 'No rule matches → "Other"'
                        : 'Matches "${hit.keyword}" → ${cats[hit.categoryId]?.name ?? '?'}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: const InputDecoration(hintText: 'Search rules', prefixIcon: Icon(Icons.search_rounded)),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final r in filtered)
                      ListTile(
                        leading: CategoryAvatar(category: cats[r.categoryId], size: 36),
                        title: Text(r.keyword),
                        subtitle: Text(cats[r.categoryId]?.name ?? 'Unknown category'),
                        onTap: () => _edit(r, cats.values.where((c) => !c.isIncome).toList()),
                        trailing: IconButton(
                          tooltip: 'Delete rule',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            await ref.read(ruleRepositoryProvider).delete(r.id!);
                            ref.refreshData();
                          },
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

  Future<void> _edit(CategoryRule? existing, List<Category> categories) async {
    final keyword = TextEditingController(text: existing?.keyword ?? '');
    int? categoryId = existing?.categoryId ?? (categories.isEmpty ? null : categories.first.id);
    final formKey = GlobalKey<FormState>();
    final repo = ref.read(ruleRepositoryProvider);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New rule' : 'Edit rule'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: keyword,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Keyword', hintText: 'e.g. jollibee', counterText: ''),
                validator: (v) => (v == null || v.trim().length < 2) ? 'At least 2 characters' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => categoryId = v,
                validator: (v) => v == null ? 'Pick a category' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final kw = keyword.text.trim().toLowerCase();
              if (await repo.keywordExists(kw, exceptId: existing?.id)) {
                if (ctx.mounted) showSnack(ctx, 'There is already a rule for "$kw"', error: true);
                return;
              }
              if (existing == null) {
                await repo.insert(CategoryRule(keyword: kw, categoryId: categoryId!));
              } else {
                await repo.update(CategoryRule(id: existing.id, keyword: kw, categoryId: categoryId!, priority: existing.priority));
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) ref.refreshData();
  }
}
