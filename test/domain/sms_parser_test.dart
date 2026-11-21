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
}
