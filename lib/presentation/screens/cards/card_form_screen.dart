import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ewallet_mask.dart';
import '../../../core/money.dart';
import '../../../data/models/payment_card.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_card_view.dart';

class CardFormScreen extends ConsumerStatefulWidget {
  const CardFormScreen({super.key, this.existing});
  final PaymentCard? existing;

  @override
  ConsumerState<CardFormScreen> createState() => _CardFormScreenState();
}

class _CardFormScreenState extends ConsumerState<CardFormScreen> {
  static const palette = <Color>[
    Color(0xFF1E3A8A), Color(0xFF0F766E), Color(0xFF7C2D12), Color(0xFFB91C1C), Color(0xFF6D28D9),
    Color(0xFF0369A1), Color(0xFF15803D), Color(0xFFBE185D), Color(0xFF334155), Color(0xFF111827),
  ];

  final _form = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _last4;
  late final TextEditingController _mobile;
  late final TextEditingController _balance;
  late CardType _type;
  late Color _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nickname = TextEditingController(text: e?.nickname ?? '');
    _last4 = TextEditingController(text: e?.last4 ?? '');
    _mobile = TextEditingController(text: e?.mobileNumber ?? '');
    _balance = TextEditingController(text: e == null ? '' : Money.toInput(e.balance < 0 ? 0 : e.balance));
    _type = e?.type ?? CardType.credit;
    _color = Color(e?.color ?? palette.first.toARGB32());
    _nickname.addListener(() => setState(() {}));
    _last4.addListener(() => setState(() {}));
    _mobile.addListener(() => setState(() {}));
  }

  bool get _isWallet => _type == CardType.ewallet;

  /// E-wallets are identified by their mobile number; the last 4 digits
  /// (used for SMS matching) come from it.
  String? get _normalizedMobile => _isWallet ? normalizePhMobileNumber(_mobile.text) : null;

  String get _effectiveLast4 {
    final m = _normalizedMobile;
    if (m != null && m.length >= 4) return m.substring(m.length - 4);
    return _last4.text;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _last4.dispose();
    _mobile.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(cardRepositoryProvider);
    final e = widget.existing;
    final balance = Money.parse(_balance.text)!;
    try {
      if (e == null) {
        await repo.insert(PaymentCard(
          nickname: _nickname.text.trim(),
          last4: _effectiveLast4,
          type: _type,
          color: _color.toARGB32(),
          mobileNumber: _normalizedMobile,
          balance: balance,
          createdAt: DateTime.now(),
        ));
      } else {
        // Only overwrite the balance if the user changed the field, so money
        // moved by transactions while this screen was open isn't lost.
        final shown = e.balance < 0 ? 0 : e.balance;
        if (balance != shown) await repo.setBalance(e.id, balance);
        await repo.update(e.copyWith(
          nickname: _nickname.text.trim(),
          last4: _effectiveLast4,
          type: _type,
          color: _color.toARGB32(),
          mobileNumber: () => _normalizedMobile,
        ));
      }
      ref.refreshData();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save card: $err', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider).asDataOrNull ?? const <PaymentCard>[];
    final preview = PaymentCard(
      nickname: _nickname.text.trim().isEmpty ? 'Card nickname' : _nickname.text.trim(),
      last4: _effectiveLast4.padRight(4, '•'),
      type: _type,
      color: _color.toARGB32(),
      mobileNumber: _normalizedMobile,
      createdAt: DateTime.now(),
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add card or e-wallet' : 'Edit ${widget.existing!.nickname}')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(child: PaymentCardView(card: preview, width: 300)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nickname,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nickname', hintText: 'e.g. BDO Mastercard', counterText: ''),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Give the card a nickname' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CardType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final t in CardType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            if (_isWallet)
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\s-]'))],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: 'e.g. 0912 345 6768',
                  helperText: 'Shown masked in the app, e.g. 09******768.',
                ),
                validator: (v) {
                  final n = normalizePhMobileNumber(v ?? '');
                  if (!RegExp(r'^09\d{9}$').hasMatch(n)) return 'Enter an 11-digit mobile number like 09123456768';
                  return null;
                },
              )
            else
              TextFormField(
                controller: _last4,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Last 4 digits',
                  helperText: 'Used to match SMS alerts. Never enter the full card number.',
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || !RegExp(r'^\d{4}$').hasMatch(v)) return 'Enter exactly 4 digits';
                  final clash = cards.any((c) => c.last4 == v && c.id != widget.existing?.id);
                  if (clash) return 'You already have a card ending in $v';
                  return null;
                },
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _balance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: _type == CardType.credit ? 'Available credit now' : 'Current balance',
                hintText: '0.00',
                prefixText: '${ref.watch(currencyProvider).symbol} ',
                helperText: widget.existing == null
                    ? 'How much is in this account today. Expenses paid with it are taken from this.'
                    : 'Change this if it doesn\'t match your real balance.',
                helperMaxLines: 2,
              ),
              validator: (v) => validateAmount(v, allowZero: true),
            ),
            const SizedBox(height: 20),
            Text('Color', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            ColorPickerField(colors: palette, selected: _color, onChanged: (c) => setState(() => _color = c)),
            const SizedBox(height: 32),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
