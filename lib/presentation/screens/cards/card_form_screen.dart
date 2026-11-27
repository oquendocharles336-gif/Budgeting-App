import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ewallet_mask.dart';
import '../../../core/money.dart';
import '../../../core/wallet_apps.dart';
import '../../../data/models/payment_card.dart';
import '../../../domain/services/phone_access_service.dart';
import '../../providers/app_state_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_card_view.dart';
import '../../widgets/phone_access_widgets.dart';

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

  /// Free automatic tracking: on/off, and which app's notifications to
  /// read (null = bank SMS alerts only).
  late bool _track;
  WalletApp? _app;
  bool _appTouched = false;
  bool _connecting = false;

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
    _track = e?.tracksAutomatically ?? false;
    _app = e?.walletApp;
    _appTouched = e?.notifyApp != null;
    _nickname.addListener(() => setState(() {
          // Suggest the app from the nickname ("Maya" -> Maya) until picked.
          if (!_appTouched) _app = WalletApp.guess(_nickname.text);
        }));
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
    final now = DateTime.now();
    final notifyApp = _track ? _app?.id : null;
    // Only payments from now on are tracked: today's balance already
    // includes everything before.
    final trackSince = _track ? (e?.autoTrackSince ?? now) : null;
    try {
      if (e == null) {
        await repo.insert(PaymentCard(
          nickname: _nickname.text.trim(),
          last4: _effectiveLast4,
          type: _type,
          color: _color.toARGB32(),
          mobileNumber: _normalizedMobile,
          balance: balance,
          notifyApp: notifyApp,
          autoTrackSince: trackSince,
          createdAt: now,
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
          notifyApp: () => notifyApp,
          autoTrackSince: () => trackSince,
        ));
      }
      // Tell the notification listener which apps to keep.
      await ref.read(autoTrackServiceProvider).syncWatchList();
      ref.refreshData();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save card: $err', error: true);
      }
    }
  }

  Future<void> _connectNotifications() async {
    setState(() => _connecting = true);
    final ok = await allowPhoneAccess(context, ref, PhoneAccess.walletNotifications);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      if (ok) _track = true;
    });
  }

  /// "Track automatically (free)": app notifications (Maya, GCash, ...)
  /// and bank SMS alerts, read on this phone only.
  Widget _autoTrackSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final access = ref.watch(phoneAccessProvider).asDataOrNull;
    final listenerOn = access?.walletNotifications ?? false;
    final smsOn = access?.sms ?? false;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bolt_rounded),
              title: const Text('Track payments automatically (free)'),
              subtitle: const Text('Every payment is added to Activity and taken from this balance. Offline, on this phone only.'),
              value: _track,
              onChanged: (v) => setState(() => _track = v),
            ),
            if (_track) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<WalletApp?>(
                initialValue: _app,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Read payment notifications from'),
                items: [
                  for (final a in WalletApp.values) DropdownMenuItem<WalletApp?>(value: a, child: Text('${a.label} app')),
                  const DropdownMenuItem<WalletApp?>(value: null, child: Text('No app (bank SMS alerts only)')),
                ],
                onChanged: (v) => setState(() {
                  _app = v;
                  _appTouched = true;
                }),
              ),
              const SizedBox(height: 12),
              if (_app != null) ...[
                if (listenerOn)
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: StatusColors.ok(context), size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${_app!.label} notifications connected', style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _connecting ? null : _connectNotifications,
                      icon: const Icon(Icons.notifications_active_rounded),
                      label: const Text('Connect App Notifications (Free)'),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  listenerOn
                      ? 'When the ${_app!.label} app shows a payment ("You paid ₱150 to ..."), Pitaka records it here the next time you open it.'
                      : 'Turn on "Notification access" for Pitaka. Only ${_app!.label} notifications are kept, and they never leave '
                          'your phone. If the switch is greyed out: App info > ⋮ > Allow restricted settings.',
                  style: muted,
                ),
              ],
              if (!_isWallet || _app == null) ...[
                const SizedBox(height: 8),
                Text(
                  smsOn
                      ? 'Bank SMS alerts that mention ••${_effectiveLast4.isEmpty ? '1234' : _effectiveLast4} are recorded too.'
                      : 'To also record bank SMS alerts, allow "Read bank texts" in Settings > Phone permissions.',
                  style: muted,
                ),
              ],
            ],
          ],
        ),
      ),
    );
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
            if (Platform.isAndroid) ...[
              const SizedBox(height: 24),
              _autoTrackSection(context),
            ],
            const SizedBox(height: 32),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
