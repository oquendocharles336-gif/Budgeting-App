import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/repositories/account_ledger.dart';
import 'package:budgeting_app/domain/services/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionEntry _tx(TransactionKind kind, int amount, {int? from, int? to}) {
  final now = DateTime(2026, 1, 1);
  return TransactionEntry(
    id: 1,
    amount: amount,
    kind: kind,
    description: 'x',
    cardId: from,
    toCardId: to,
    date: now,
    affectsBalance: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('AccountLedger.effects', () {
    test('expense takes money out of the paying account', () {
      expect(AccountLedger.effects(_tx(TransactionKind.expense, 500, from: 3)), [(3, -500)]);
    });

    test('income adds to the receiving account (null = Cash)', () {
      expect(AccountLedger.effects(_tx(TransactionKind.income, 1200)), [(null, 1200)]);
    });

    test('transfer moves money between two accounts', () {
      expect(AccountLedger.effects(_tx(TransactionKind.transfer, 300, from: null, to: 7)), [(null, -300), (7, 300)]);
    });
  });

  group('PinAttempts.waitAfter', () {
    final now = DateTime(2026, 1, 1, 12);
    test('no wait for the first 4 mistakes', () {
      expect(PinAttempts.waitAfter(4, now), isNull);
    });
    test('30 s after 5, doubling, capped at 16 min', () {
      expect(PinAttempts.waitAfter(5, now), now.add(const Duration(seconds: 30)));
      expect(PinAttempts.waitAfter(6, now), now.add(const Duration(seconds: 60)));
      expect(PinAttempts.waitAfter(20, now), now.add(const Duration(seconds: 960)));
    });
  });
}
