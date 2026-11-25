import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/category.dart';
import '../../../data/models/transaction_entry.dart';
import '../../../domain/import/deduplicator.dart';
import '../../../domain/import/transaction_import_service.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Review list shared by CSV and SMS import. Nothing is saved until the
/// user taps the save button.
class ImportReview extends ConsumerStatefulWidget {
  const ImportReview({super.key, required this.candidates, this.header, this.onSaved});

  final List<ImportCandidate> candidates;
  final Widget? header;
  final VoidCallback? onSaved;

  @override
  ConsumerState<ImportReview> createState() => _ImportReviewState();
}

class _ImportReviewState extends ConsumerState<ImportReview> {
  bool _saving = false;

  List<ImportCandidate> get _items => widget.candidates;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await ref.read(importServiceProvider).commit(_items);
      ref.refreshData();
      if (!mounted) return;
      showSnack(
        context,
        'Saved ${result.inserted} transaction${result.inserted == 1 ? '' : 's'}'
        '${result.skipped > 0 ? ', skipped ${result.skipped}' : ''}.',
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Import failed: $e', error: true);
    }
  }

  Future<void> _pickCategory(ImportCandidate c, List<Category> categories) async {
    final id = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final cat in categories.where((x) => x.isIncome == (c.raw.kind == TransactionKind.income)))
              ListTile(
                leading: CategoryAvatar(category: cat, size: 36),
                title: Text(cat.name),
                selected: cat.id == c.categoryId,
                onTap: () => Navigator.pop(ctx, cat.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) setState(() => c.categoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider).asDataOrNull ?? const <Category>[];
    final catMap = {for (final c in categories) c.id: c};
    final selected = _items.where((c) => c.selected).length;
    final dupes = _items.where((c) => c.isDuplicate).length;

    if (_items.isEmpty) {
      return Column(
        children: [
          ?widget.header,
          const Expanded(
            child: EmptyState(
              icon: Icons.inbox_rounded,
              title: 'Nothing to import',
              message: 'No transactions were found for this card.',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?widget.header,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_items.length} found · ${_items.length - dupes} new'
                              '${dupes > 0 ? ' · $dupes already saved' : ''}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              final all = selected != _items.length;
                              for (final c in _items) {
                                c.selected = all;
                              }
                            }),
                            child: Text(selected == _items.length ? 'Select none' : 'Select all'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              final c = _items[i - 1];
              final cat = catMap[c.categoryId];
              return CheckboxListTile(
                value: c.selected,
                onChanged: (v) => setState(() => c.selected = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                isThreeLine: true,
                title: Row(
                  children: [
                    Expanded(child: Text(c.raw.description, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    AmountText(c.raw.amount, kind: c.raw.kind, colored: true, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('EEE, MMM d, yyyy').format(c.raw.date)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: CategoryAvatar(category: cat, size: 20),
                          label: Text(cat?.name ?? 'Category'),
                          onPressed: () => _pickCategory(c, categories),
                        ),
                        if (c.isDuplicate)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: scheme.tertiaryContainer,
                            label: Text(
                              c.duplicate == DuplicateReason.externalId ? 'Already imported' : 'Looks like a duplicate',
                              style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    if (c.raw.originalText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          c.raw.originalText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _saving || selected == 0 ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save $selected transaction${selected == 1 ? '' : 's'}'),
            ),
          ),
        ),
      ],
    );
  }
}
