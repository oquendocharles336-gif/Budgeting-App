import 'package:budgeting_app/core/ewallet_mask.dart';
import 'package:budgeting_app/data/models/payment_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('maskEWalletNumber', () {
    test('keeps first 2 and last 3 digits', () {
      expect(maskEWalletNumber('09123456768'), '09******768');
    });

    test('strips spaces and dashes', () {
      expect(maskEWalletNumber('0912 345 6768'), '09******768');
      expect(maskEWalletNumber('0912-345-6768'), '09******768');
    });

    test('normalizes (+63), +63 and 63 prefixes to 0', () {
      expect(maskEWalletNumber('(+63) 9123456768'), '09******768');
      expect(maskEWalletNumber('(+63) 912-345-6768'), '09******768');
      expect(maskEWalletNumber('+639123456768'), '09******768');
      expect(maskEWalletNumber('639123456768'), '09******768');
    });

    test('returns input unchanged when too short to mask', () {
      expect(maskEWalletNumber(''), '');
      expect(maskEWalletNumber('0912'), '0912');
      expect(maskEWalletNumber('123456'), '123456');
    });

    test('masks the shortest allowed length', () {
      expect(maskEWalletNumber('1234567'), '12**567');
    });
  });

  group('normalizePhMobileNumber', () {
    test('leaves a local number alone', () {
      expect(normalizePhMobileNumber('09123456768'), '09123456768');
    });

    test('converts international formats', () {
      expect(normalizePhMobileNumber('(+63) 912 345 6768'), '09123456768');
    });
  });

  group('PaymentCard display', () {
    PaymentCard card(CardType type, {String? mobile}) => PaymentCard(
          nickname: 'GCash',
          last4: '6768',
          type: type,
          color: 0xFF2563EB,
          mobileNumber: mobile,
          createdAt: DateTime(2026),
        );

    test('e-wallet with a number shows it masked', () {
      final c = card(CardType.ewallet, mobile: '09123456768');
      expect(c.maskedNumber, '09******768');
      expect(c.label, 'GCash 09******768');
      expect(c.shortLabel, 'GCash 09******768');
      // Full number is kept for storage.
      expect(c.toMap()['mobile_number'], '09123456768');
    });

    test('other cards keep the last-4 display', () {
      final c = card(CardType.credit, mobile: '09123456768');
      expect(c.label, 'GCash •••• 6768');
      expect(c.shortLabel, 'GCash ••6768');
    });
  });
}
