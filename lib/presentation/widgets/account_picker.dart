import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/models/payment_card.dart';
import '../providers/app_state_providers.dart';
import '../providers/data_providers.dart';
import 'common.dart';

/// The picked account. A wrapper, because `null` (Cash) is a valid choice.
typedef AccountChoice = ({int? accountId});

IconData accountIcon(PaymentCard? c) => c == null
    ? Icons.payments_rounded
    : (c.type == CardType.ewallet ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded);

/// Bottom sheet: Cash plus each active account, with balances. Returns
/// null if dismissed.
Future<AccountChoice?> pickAccountSheet(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  String? message,
}) async {
  final accounts = await ref.read(cardsProvider.future);
  final cash = await ref.read(cashBalanceProvider.future);
  if (!context.mounted) return null;
  final symbol = ref.read(currencyProvider).symbol;
  return showModalBottomSheet<AccountChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(message, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ),
            ListTile(
              leading: Icon(accountIcon(null)),
              title: const Text('Cash'),
              subtitle: Text(Money.format(cash, symbol: symbol)),
              onTap: () => Navigator.pop(ctx, (accountId: null)),
            ),
            for (final c in accounts)
              ListTile(
                leading: Icon(accountIcon(c), color: Color(c.color)),
                title: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${c.balanceLabel}: ${Money.format(c.balance, symbol: symbol)}'),
                onTap: () => Navigator.pop(ctx, (accountId: c.id)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Dropdown of Cash plus each active account, for forms.
class AccountDropdown extends ConsumerWidget {
  const AccountDropdown({super.key, required this.value, required this.onChanged, required this.label});
  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cardsProvider).asDataOrNull ?? const <PaymentCard>[];
    final cash = ref.watch(cashBalanceProvider).asDataOrNull;
    final symbol = ref.watch(currencyProvider).symbol;
    final safe = accounts.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<int?>(
      initialValue: safe,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Row(children: [
            Icon(accountIcon(null)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(cash == null ? 'Cash' : 'Cash · ${Money.format(cash, symbol: symbol)}', overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        for (final c in accounts)
          DropdownMenuItem<int?>(
            value: c.id,
            child: Row(children: [
              Icon(accountIcon(c), color: Color(c.color)),
              const SizedBox(width: 10),
              Flexible(child: Text('${c.label} · ${Money.format(c.balance, symbol: symbol)}', overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
