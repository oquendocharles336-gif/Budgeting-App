import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/dates.dart';
import '../../domain/import/deduplicator.dart';
import '../models/debt.dart';
import '../models/payment_card.dart';
import '../models/transaction_entry.dart';
import 'default_data.dart';

/// Sample data for trying the app (Settings > Load sample data).
/// Generates ~2 months of realistic Philippine spending.
class SeedData {
  SeedData._();

  static Future<void> load(Database db, {DateTime? now, int seed = 42}) async {
    final today = now ?? DateTime.now();
    final rnd = Random(seed);

    await db.transaction((txn) async {
      final created = today.millisecondsSinceEpoch;
      final bdo = await txn.insert('cards', PaymentCard(
        nickname: 'BDO Mastercard',
        last4: '1234',
        type: CardType.credit,
        color: 0xFF1E3A8A,
        createdAt: today,
      ).toMap());
      final bpi = await txn.insert('cards', PaymentCard(
        nickname: 'BPI Debit',
        last4: '5678',
        type: CardType.debit,
        color: 0xFFB91C1C,
        createdAt: today,
      ).toMap());
      final gcash = await txn.insert('cards', PaymentCard(
        nickname: 'GCash',
        last4: '6768',
        type: CardType.ewallet,
        color: 0xFF2563EB,
        mobileNumber: '09123456768',
        createdAt: today,
      ).toMap());

      // (description, category, min pesos, max pesos, card or null=cash)
      final templates = <(String, int, int, int, int?)>[
        ('Jollibee', DefaultData.food, 120, 450, null),
        ('Starbucks', DefaultData.food, 160, 320, bdo),
        ('GrabFood', DefaultData.food, 250, 700, gcash),
        ('Puregold groceries', DefaultData.food, 800, 3500, bpi),
        ('Jeepney fare', DefaultData.transport, 13, 40, null),
        ('Grab ride', DefaultData.transport, 150, 450, gcash),
        ('Petron fuel', DefaultData.transport, 800, 2000, bdo),
        ('LRT Beep load', DefaultData.transport, 100, 300, null),
        ('Shopee order', DefaultData.shopping, 200, 1800, bdo),
        ('Lazada order', DefaultData.shopping, 300, 2500, bdo),
        ('Mercury Drug', DefaultData.health, 150, 900, null),
        ('Netflix', DefaultData.entertainment, 549, 549, bdo),
        ('SM Cinema', DefaultData.entertainment, 350, 700, bpi),
        ('National Book Store', DefaultData.education, 150, 900, bpi),
      ];

      final salaryRow = await txn.query('categories', columns: ['id'], where: "kind = 'income' AND name = 'Salary'", limit: 1);
      final salaryCategory = salaryRow.isEmpty ? DefaultData.other : salaryRow.first['id'] as int;

      Future<int> categoryId(String name) async {
        final row = await txn.query('categories', columns: ['id'], where: "kind = 'expense' AND name = ?", whereArgs: [name], limit: 1);
        return row.isEmpty ? DefaultData.utilities : row.first['id'] as int;
      }

      final electricityId = await categoryId(DefaultData.electricity.name);
      final wifiId = await categoryId(DefaultData.wifi.name);
      final waterId = await categoryId(DefaultData.water.name);

      final start = DateTime(today.year, today.month - 1, 1);
      for (var day = start; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
        final count = 1 + rnd.nextInt(3);
        for (var i = 0; i < count; i++) {
          final t = templates[rnd.nextInt(templates.length)];
          final pesos = t.$3 + (t.$4 > t.$3 ? rnd.nextInt(t.$4 - t.$3) : 0);
          final amount = pesos * 100 + (rnd.nextBool() ? 0 : rnd.nextInt(100));
          final date = DateTime(day.year, day.month, day.day, 8 + rnd.nextInt(13), rnd.nextInt(60));
          await txn.insert('transactions', _tx(t.$1, t.$2, t.$5, amount, date, created));
        }
        // Monthly utility bills on the 5th.
        if (day.day == 5) {
          await txn.insert('transactions', _tx('Meralco bill', electricityId, null, 245000, day, created));
          await txn.insert('transactions', _tx('PLDT Fibr', wifiId, bdo, 169900, day, created));
          await txn.insert('transactions', _tx('Maynilad', waterId, null, 68000, day, created));
        }
        // Salary on the 15th and 30th.
        if (day.day == 15 || day.day == 30) {
          await txn.insert('transactions', _tx('Salary', salaryCategory, bpi, 1800000, day, created,
              kind: TransactionKind.income));
        }
      }

      // Budgets for this month and last month.
      for (final m in [Dates.previousMonth(today), today]) {
        final key = Dates.monthKey(m);
        await txn.insert('budgets', {'month': key, 'category_id': null, 'amount': 2500000});
        await txn.insert('budgets', {'month': key, 'category_id': DefaultData.food, 'amount': 800000});
        await txn.insert('budgets', {'month': key, 'category_id': DefaultData.transport, 'amount': 400000});
        await txn.insert('budgets', {'month': key, 'category_id': DefaultData.shopping, 'amount': 300000});
      }

      final loanId = await txn.insert('debts', Debt(
        creditor: 'Tita Lorna',
        type: DebtType.personal,
        lenderType: LenderType.family,
        totalAmount: 1500000,
        initialPaid: 300000,
        termMonths: 6,
        dueDay: today.add(const Duration(days: 10)).day,
        notes: 'Laptop loan',
        createdAt: today,
      ).toMap());
      await txn.insert('debt_payments', DebtPayment(
        debtId: loanId,
        amount: 200000,
        date: today.subtract(const Duration(days: 12)),
        note: 'GCash transfer',
      ).toMap());
      await txn.insert('debts', Debt(
        creditor: 'Home Credit',
        type: DebtType.installment,
        lenderType: LenderType.lendingApp,
        termMonths: 12,
        totalAmount: 2400000,
        initialPaid: 800000,
        dueDay: today.add(const Duration(days: 3)).day,
        interestRateBp: 299,
        notes: 'Phone installment',
        createdAt: today,
      ).toMap());
    });
  }

  static Map<String, Object?> _tx(
    String description,
    int categoryId,
    int? cardId,
    int amount,
    DateTime date,
    int created, {
    TransactionKind kind = TransactionKind.expense,
  }) =>
      {
        'amount': amount,
        'kind': kind.name,
        'description': description,
        'category_id': categoryId,
        'card_id': cardId,
        'date': date.millisecondsSinceEpoch,
        'notes': null,
        'source': TransactionSourceType.manual.dbValue,
        'external_id': null,
        'dedup_hash': Deduplicator.hashFor(
          date: date,
          amount: amount,
          kind: kind,
          description: description,
          cardId: cardId,
        ),
        'created_at': created,
        'updated_at': created,
      };
}
