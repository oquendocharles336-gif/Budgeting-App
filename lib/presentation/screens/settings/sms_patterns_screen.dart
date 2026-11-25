import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/sms_pattern.dart';
import '../../../data/models/transaction_entry.dart';
import '../../../domain/sms/sms_parser.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Edit the regex patterns used to read bank SMS alerts, with a tester.
class SmsPatternsScreen extends ConsumerWidget {
  const SmsPatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(smsPatternsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS patterns'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v != 'reset') return;
              final ok = await confirm(context, title: 'Reset patterns?', message: 'Your changes are replaced by the built-in examples.', confirmLabel: 'Reset');
              if (!ok) return;
              await ref.read(smsPatternRepositoryProvider).resetToDefaults();
              ref.refreshData();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset to defaults'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmsPatternEditor())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New pattern'),
      ),
      body: AsyncView<List<SmsPattern>>(
        value: patterns,
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Text(
              'Each bank words its texts differently. A pattern is a regular expression with named parts: '
              '(?<amount>…) is required; (?<merchant>…), (?<last4>…) and (?<ref>…) are optional. '
              'Use the tester to paste one of your real alerts and check it.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final p in list)
                    SwitchListTile(
                      title: Text(p.bankName),
                      subtitle: Text(
                        p.kind == TransactionKind.income ? 'Money in' : 'Money out',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: p.enabled,
                      onChanged: (v) async {
                        await ref.read(smsPatternRepositoryProvider).update(p.copyWith(enabled: v));
                        ref.refreshData();
                      },
                      secondary: IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SmsPatternEditor(existing: p)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SmsPatternEditor extends ConsumerStatefulWidget {
  const SmsPatternEditor({super.key, this.existing});
  final SmsPattern? existing;

  @override
  ConsumerState<SmsPatternEditor> createState() => _SmsPatternEditorState();
}

class _SmsPatternEditorState extends ConsumerState<SmsPatternEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sender;
  late final TextEditingController _body;
  final _sample = TextEditingController();
  late TransactionKind _kind;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.bankName ?? '');
    _sender = TextEditingController(text: e?.senderPattern ?? '');
    _body = TextEditingController(text: e?.bodyPattern ?? r'(?:PHP|P|₱)\s?(?<amount>[\d,]+(?:\.\d{1,2})?)\s+at\s+(?<merchant>.+?)(?=\.|$)');
    _kind = e?.kind ?? TransactionKind.expense;
  }

  @override
  void dispose() {
    for (final c in [_name, _sender, _body, _sample]) {
      c.dispose();
    }
    super.dispose();
  }

  String _testResult() {
    final err = SmsParser.validate(_body.text);
    if (err != null) return err;
    if (_sample.text.trim().isEmpty) return 'Paste an SMS above to test.';
    final parser = SmsParser([
      SmsPattern(bankName: _name.text.isEmpty ? 'Test' : _name.text, bodyPattern: _body.text, kind: _kind),
    ]);
    final r = parser.parse(SmsMessage(id: 't', address: '', body: _sample.text, date: DateTime.now()));
    if (r == null) return 'No match (or the message looks like an OTP).';
    return 'Amount: ${r.amount / 100}\nMerchant: ${r.merchant}\nCard last 4: ${r.last4 ?? '—'}\nRef: ${r.reference ?? '—'}';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(smsPatternRepositoryProvider);
    final p = SmsPattern(
      id: widget.existing?.id,
      bankName: _name.text.trim(),
      senderPattern: _sender.text.trim(),
      bodyPattern: _body.text,
      kind: _kind,
      enabled: widget.existing?.enabled ?? true,
    );
    if (p.id == null) {
      await repo.insert(p);
    } else {
      await repo.update(p);
    }
    ref.refreshData();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New pattern' : 'Edit pattern'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(smsPatternRepositoryProvider).delete(widget.existing!.id!);
                ref.refreshData();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. BDO credit card'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sender,
              decoration: const InputDecoration(
                labelText: 'Sender filter (optional regex)',
                hintText: 'e.g. ^BDO',
                helperText: 'Leave empty to check messages from any sender',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                try {
                  RegExp(v);
                  return null;
                } on FormatException catch (e) {
                  return 'Invalid: ${e.message}';
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(labelText: 'Message pattern (regex)'),
              onChanged: (_) => setState(() {}),
              validator: (v) => SmsParser.validate(v ?? ''),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TransactionKind>(
              segments: const [
                ButtonSegment(value: TransactionKind.expense, label: Text('Money out')),
                ButtonSegment(value: TransactionKind.income, label: Text('Money in')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SectionHeader('Test it'),
            TextField(
              controller: _sample,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Paste a real SMS alert here'),
            ),
            const SizedBox(height: 8),
            AppCard(child: Text(_testResult())),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save pattern')),
          ],
        ),
      ),
    );
  }
}
