import 'package:budgeting_app/data/db/default_data.dart';
import 'package:budgeting_app/data/models/sms_pattern.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/domain/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

SmsMessage sms(String body, {String address = 'BANK', String id = '1'}) =>
    SmsMessage(id: id, address: address, body: body, date: DateTime(2026, 11, 20, 12));

void main() {
  final parser = SmsParser(DefaultData.smsPatterns);

  test('default patterns compile', () {
    expect(parser.invalidPatterns, isEmpty);
  });

  test('card ending ... used for PHP ... at MERCHANT', () {
    final r = parser.parse(sms(
      'Your BDO Credit Card ending 1234 was used for PHP 1,250.00 at JOLLIBEE SM NORTH on 11/20/26. Not you? Call us.',
    ))!;
    expect(r.amount, 125000);
    expect(r.last4, '1234');
    expect(r.merchant, 'JOLLIBEE SM NORTH');
    expect(r.kind, TransactionKind.expense);
  });

  test('PHP ... charged to card xxxx5678 at MERCHANT', () {
    final r = parser.parse(sms('PHP 899.00 was charged to your card xxxx5678 at SHOPEE PH on 2026-11-19.'))!;
    expect(r.amount, 89900);
    expect(r.last4, '5678');
    expect(r.merchant, 'SHOPEE PH');
  });

  test('no space after currency, acct ending', () {
    final r = parser.parse(sms('Php12,345.67 charged to acct ending 0001 at LAZADA.'))!;
    expect(r.amount, 1234567);
    expect(r.last4, '0001');
    expect(r.merchant, 'LAZADA');
  });

  test('masked card with asterisks', () {
    final r = parser.parse(sms('Your card **4321 purchase of P75.50 at 7-ELEVEN KATIPUNAN, Nov 20.'))!;
    expect(r.amount, 7550);
    expect(r.last4, '4321');
    expect(r.merchant, '7-ELEVEN KATIPUNAN');
  });

  test('e-wallet payment with reference number', () {
    final r = parser.parse(sms('You have paid PHP 350.00 to MERALCO via GCash. Ref No. 1234567890 11-20-2026'))!;
    expect(r.amount, 35000);
    expect(r.merchant, 'MERALCO');
    expect(r.last4, isNull);
    expect(r.reference, '1234567890');
    expect(r.kind, TransactionKind.expense);
  });

  test('money received is income', () {
    final r = parser.parse(sms('You have received PHP 1,000.00 from JUAN DELA CRUZ. Ref No. 99887766.'))!;
    expect(r.kind, TransactionKind.income);
    expect(r.amount, 100000);
    expect(r.merchant, 'JUAN DELA CRUZ');
    expect(r.reference, '99887766');
  });

  test('OTP messages are never parsed', () {
    expect(parser.parse(sms('Your OTP is 123456. Do not share.')), isNull);
    expect(parser.parse(sms('Your OTP for PHP 500.00 at SHOPEE is 998877. Valid for 5 mins.')), isNull);
    expect(parser.parse(sms('123456 is your OTP for login')), isNull);
  });

  test('"never share your OTP" footer does not block a real alert', () {
    final r = parser.parse(sms(
      'Your BDO Credit Card ending 1234 was used for PHP 1,250.00 at JOLLIBEE. Never share your OTP.',
    ));
    expect(r, isNotNull);
    expect(r!.merchant, 'JOLLIBEE');
  });

  test('unrelated messages are ignored', () {
    expect(parser.parse(sms('See you at 7pm later!')), isNull);
    expect(parser.parse(sms('')), isNull);
  });

  test('line breaks in the body are handled', () {
    final r = parser.parse(sms('Your card ending 1234\nwas used for PHP 99.00\nat STARBUCKS.'));
    expect(r?.amount, 9900);
    expect(r?.merchant, 'STARBUCKS');
  });

  test('sender filter', () {
    final p = SmsParser([
      const SmsPattern(bankName: 'BDO', senderPattern: r'^BDO', bodyPattern: r'PHP\s?(?<amount>[\d,.]+)'),
    ]);
    expect(p.parse(sms('PHP 100.00 spent', address: 'BDO')), isNotNull);
    expect(p.parse(sms('PHP 100.00 spent', address: 'GCASH')), isNull);
  });

  test('disabled patterns are skipped', () {
    final p = SmsParser([
      const SmsPattern(bankName: 'X', bodyPattern: r'PHP\s?(?<amount>[\d,.]+)', enabled: false),
    ]);
    expect(p.parse(sms('PHP 100.00 spent')), isNull);
  });

  test('invalid user patterns are reported, not thrown', () {
    final p = SmsParser([const SmsPattern(bankName: 'Broken', bodyPattern: r'(?<amount>[0-9+')]);
    expect(p.invalidPatterns.keys, contains('Broken'));
    expect(p.parse(sms('PHP 1')), isNull);
  });

  test('validate()', () {
    expect(SmsParser.validate(''), isNotNull);
    expect(SmsParser.validate(r'PHP (\d+)'), contains('amount'));
    expect(SmsParser.validate(r'(?<amount>[0-9+'), contains('Invalid'));
    expect(SmsParser.validate(r'PHP (?<amount>\d+)'), isNull);
  });

  test('parseAll keeps only matches', () {
    final list = parser.parseAll([
      sms('PHP 899.00 was charged to your card xxxx5678 at SHOPEE PH.', id: 'a'),
      sms('Hello there', id: 'b'),
    ]);
    expect(list.length, 1);
    expect(list.first.message.id, 'a');
  });

  group('received money (credits, incoming transfers)', () {
    // The user's list here is only the older defaults: the built-in
    // incoming rules must still read the newer wordings.
    final p = SmsParser(DefaultData.smsPatterns);

    void income(String body, int amount, {String? merchant, String? last4, String? ref, String address = 'BANK'}) {
      final r = p.parse(sms(body, address: address));
      expect(r, isNotNull, reason: body);
      expect(r!.kind, TransactionKind.income, reason: body);
      expect(r.amount, amount, reason: body);
      if (merchant != null) expect(r.merchant, merchant, reason: body);
      if (last4 != null) expect(r.last4, last4, reason: body);
      if (ref != null) expect(r.reference, ref, reason: body);
    }

    test('GCash: "received PHP 500.00 of GCash from NAME"', () {
      income('You have received PHP 500.00 of GCash from JUAN DELA CRUZ w/ MSG: lunch. Your new balance is PHP 1,200.00. Ref. No. 1012345678901.',
          50000,
          merchant: 'JUAN DELA CRUZ w/ MSG: lunch',
          ref: '1012345678901',
          address: 'GCash');
    });

    test('InstaPay: "received PHP 1,000.00 via InstaPay from NAME"', () {
      income('You have received PHP 1,000.00 via InstaPay from ANA SANTOS on 11/27/2026.', 100000, merchant: 'ANA SANTOS');
    });

    test('"received a transfer of PHP 2,500.00 from NAME"', () {
      income('You received a transfer of PHP 2,500.00 from MARIA C. Ref 778899', 250000, merchant: 'MARIA C', ref: '778899');
    });

    test('"NAME sent you PHP 300.00"', () {
      income('JUAN D. sent you PHP 300.00. Ref No. 55443322', 30000, merchant: 'JUAN D.', ref: '55443322');
    });

    test('bank credit alert with the account number first', () {
      income('Your account ending 1234 has been credited with PHP 5,000.00 on 11/27/26.', 500000,
          last4: '1234', merchant: IncomingPatterns.defaultDescription);
    });

    test('bank credit alert with the amount first', () {
      income('PHP 15,000.00 has been credited to your account ending 9876. Ref: AB12CD', 1500000, last4: '9876', ref: 'AB12CD');
    });

    test('cash in, deposit and refund', () {
      income('Cash In of P1,000.00 is successful. Ref No. 123123', 100000);
      income('Incoming transfer PHP 200.00 from PEDRO', 20000, merchant: 'PEDRO');
      income('Refund of PHP 99.00 for your order has been processed.', 9900);
    });

    test('"PHP 100 received" with no sender', () {
      income('₱100.00 received. Thank you for using Maya!', 10000);
    });

    test('a credit alert matched by a card pattern is still income', () {
      // The generic card pattern ("PHP x ... acct 1234 ... at ...") matches
      // first; the wording says money came in, so it must not be spending.
      income('PHP 750.00 was credited to acct ending 4321 at 10:30AM.', 75000, last4: '4321');
    });

    test('a user income pattern beats an earlier expense pattern', () {
      final mixed = SmsParser([
        const SmsPattern(bankName: 'Any amount', bodyPattern: r'PHP\s?(?<amount>[\d,.]+\d)'),
        const SmsPattern(bankName: 'Received', bodyPattern: r'received PHP\s?(?<amount>[\d,.]+\d)', kind: TransactionKind.income),
      ]);
      final r = mixed.parse(sms('You received PHP 400.00 from LIZA'))!;
      expect(r.kind, TransactionKind.income);
      expect(r.pattern.bankName, 'Received');
    });

    test('payments are still expenses', () {
      expect(p.parse(sms('You have paid PHP 350.00 to MERALCO via GCash. Ref No. 1234567890'))!.kind, TransactionKind.expense);
      // "payment" before "received": money out.
      final r = p.parse(sms('Your payment of PHP 1,200.00 to PLDT was received. Ref 9988.'));
      expect(r == null || r.kind == TransactionKind.expense, isTrue);
      // "received a payment": money in.
      income('You have received a payment of PHP 640.00 from KAREN L.', 64000, merchant: 'KAREN L');
    });

    test('built-in rules can be turned off (pattern tester)', () {
      final only = SmsParser(DefaultData.smsPatterns, builtInIncoming: false);
      expect(only.parse(sms('Your account ending 1234 has been credited with PHP 5,000.00')), isNull);
    });

    test('OTPs mentioning received money are still ignored', () {
      expect(p.parse(sms('Your OTP to receive PHP 500.00 is 445566.')), isNull);
    });
  });

  group('direction of an alert', () {
    test('earliest money word wins', () {
      expect(IncomingPatterns.directionOf('You have received a payment of PHP 5'), MoneyDirection.incoming);
      expect(IncomingPatterns.directionOf('Your payment of PHP 5 was received'), MoneyDirection.outgoing);
      expect(IncomingPatterns.directionOf('JUAN sent you PHP 5'), MoneyDirection.incoming);
      expect(IncomingPatterns.directionOf('You sent PHP 5 to JUAN'), MoneyDirection.outgoing);
      expect(IncomingPatterns.directionOf('PHP 5 has been sent to your account'), MoneyDirection.incoming);
      expect(IncomingPatterns.directionOf('See you at 7pm'), isNull);
    });
  });
}
