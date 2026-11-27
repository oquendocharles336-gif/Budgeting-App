import 'package:budgeting_app/core/wallet_apps.dart';
import 'package:budgeting_app/data/db/default_data.dart';
import 'package:budgeting_app/data/models/business.dart';
import 'package:budgeting_app/data/models/payment_card.dart';
import 'package:budgeting_app/data/models/sms_pattern.dart';
import 'package:budgeting_app/data/models/transaction_entry.dart';
import 'package:budgeting_app/data/sources/wallet_notifications.dart';
import 'package:budgeting_app/domain/services/auto_track_service.dart';
import 'package:budgeting_app/domain/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

WalletNotification note(String title, String text, {String pkg = 'com.paymaya'}) =>
    WalletNotification(id: '1', packageName: pkg, title: title, text: text, date: DateTime(2026, 11, 27, 12));

PaymentCard card(int id, {String last4 = '6768', String? app = 'maya', DateTime? created}) => PaymentCard(
      id: id,
      nickname: 'Maya $id',
      last4: last4,
      type: CardType.ewallet,
      color: 0xFF0F766E,
      notifyApp: app,
      autoTrackSince: DateTime(2026, 11, 1),
      createdAt: created ?? DateTime(2026, 1, id),
    );

void main() {
  final parser = SmsParser([...DefaultData.smsPatterns, ...DefaultData.notificationPatterns]);

  group('wallet notifications are parsed like SMS', () {
    test('patterns compile', () => expect(parser.invalidPatterns, isEmpty));

    test('title and text become one message', () {
      expect(note('Payment successful', "You've paid ₱150.00 to 7-Eleven.").body,
          "Payment successful. You've paid ₱150.00 to 7-Eleven.");
      expect(note('', 'You sent ₱500.00 to JUAN D.').body, 'You sent ₱500.00 to JUAN D.');
      // A title repeated inside the text isn't doubled.
      expect(note('You paid', 'You paid ₱20 to Jeep').body, 'You paid ₱20 to Jeep');
    });

    test('"You\'ve paid ₱150.00 to 7-Eleven via QR Ph" (Maya)', () {
      final r = parser.parse(note('Payment successful', "You've paid ₱150.00 to 7-Eleven via QR Ph.").toMessage())!;
      expect(r.amount, 15000);
      expect(r.merchant, '7-Eleven');
      expect(r.kind, TransactionKind.expense);
    });

    test('"Payment of PHP 1,299.00 to SHOPEE" ', () {
      final r = parser.parse(note('Maya', 'Payment of PHP 1,299.00 to SHOPEE was successful.').toMessage())!;
      expect(r.amount, 129900);
      expect(r.merchant, 'SHOPEE');
    });

    test('received money is income', () {
      final r = parser.parse(note('', 'You received ₱1,000.00 from ANA S.', pkg: 'com.globe.gcash.android').toMessage())!;
      expect(r.amount, 100000);
      expect(r.kind, TransactionKind.income);
    });

    test('OTP notifications are ignored', () {
      expect(parser.parse(note('Maya', 'Your OTP is 123456. Never share it.').toMessage()), isNull);
    });
  });

  group('received money from notifications and SMS', () {
    test('GCash "received PHP x of GCash from NAME" notification is income', () {
      final r = parser.parse(note('GCash', 'You have received PHP 500.00 of GCash from JUAN DELA CRUZ. Ref. No. 1012345678901.',
              pkg: 'com.globe.gcash.android')
          .toMessage())!;
      expect(r.kind, TransactionKind.income);
      expect(r.amount, 50000);
      expect(r.merchant, 'JUAN DELA CRUZ');
      expect(r.reference, '1012345678901');
    });

    test('Maya "NAME sent you ₱x" notification is income', () {
      final r = parser.parse(note('Money received', 'ANA SANTOS sent you ₱1,250.00.').toMessage())!;
      expect(r.kind, TransactionKind.income);
      expect(r.amount, 125000);
      expect(r.merchant, 'ANA SANTOS');
    });

    test('a notification whose whole alert is the title still parses', () {
      // The listener sends the title as the text when the text is empty.
      final r = parser.parse(note('', 'You received ₱300.00').toMessage())!;
      expect(r.kind, TransactionKind.income);
      expect(r.amount, 30000);
    });

    test('bank credit SMS with the account number goes to that account', () {
      final r = parser.parse(SmsMessage(
        id: 's1',
        address: 'BDO',
        body: 'Your account ending 1111 has been credited with PHP 2,000.00 on 11/27/26.',
        date: DateTime(2026, 11, 27, 9),
      ))!;
      expect(r.kind, TransactionKind.income);
      expect(AutoTrackService.cardForSms([card(1), card(2, last4: '1111', app: null)], r)!.id, 2);
    });

    test('an e-wallet SMS without an account number goes to the account linked to the sender', () {
      final r = parser.parse(SmsMessage(
        id: 's2',
        address: 'GCash',
        body: 'You have received PHP 250.00 of GCash from LIZA M. Ref. No. 9001',
        date: DateTime(2026, 11, 27, 9),
      ))!;
      expect(r.kind, TransactionKind.income);
      expect(r.last4, isNull);
      expect(AutoTrackService.cardForSms([card(1), card(2, last4: '2222', app: 'gcash')], r)!.id, 2);
      // Two GCash accounts: ambiguous, so nothing is guessed.
      expect(AutoTrackService.cardForSms([card(2, app: 'gcash'), card(3, last4: '3333', app: 'gcash')], r), isNull);
      // No GCash account tracked: skipped.
      expect(AutoTrackService.cardForSms([card(1)], r), isNull);
    });

    test('an SMS for a card number that isn\'t tracked is never moved to another account', () {
      final r = parser.parse(SmsMessage(
        id: 's3',
        address: 'BDO',
        body: 'PHP 5,000.00 has been credited to your account ending 9999.',
        date: DateTime(2026, 11, 27, 9),
      ))!;
      expect(r.last4, '9999');
      expect(AutoTrackService.cardForSms([card(1, app: 'bdo_pay')], r), isNull);
    });

    test('SMS senders map to apps', () {
      expect(WalletApp.forSmsSender('GCash'), WalletApp.gcash);
      expect(WalletApp.forSmsSender('PayMaya'), WalletApp.maya);
      expect(WalletApp.forSmsSender('SeaBank'), WalletApp.maribank);
      expect(WalletApp.forSmsSender('+639171234567'), isNull);
    });
  });

  group('apps', () {
    test('package names and ids round-trip', () {
      for (final a in WalletApp.values) {
        expect(WalletApp.fromId(a.id), a);
        expect(WalletApp.forPackage(a.packageName), a);
      }
      expect(WalletApp.forPackage('com.whatsapp'), isNull);
    });

    test('guessed from the nickname', () {
      expect(WalletApp.guess('My Maya'), WalletApp.maya);
      expect(WalletApp.guess('GCash savings'), WalletApp.gcash);
      expect(WalletApp.guess('SeaBank'), WalletApp.maribank);
      expect(WalletApp.guess('BPI debit'), isNull);
    });
  });

  group('which account a notification goes to', () {
    test('the one whose last 4 digits it mentions', () {
      expect(AutoTrackService.pickCard([card(1), card(2, last4: '1111')], '1111')!.id, 2);
    });

    test('otherwise the oldest connected account', () {
      expect(AutoTrackService.pickCard([card(2), card(1)], null)!.id, 1);
      expect(AutoTrackService.pickCard(const [], null), isNull);
    });

    test('tracking needs a start time and an active account', () {
      expect(card(1).tracksAutomatically, isTrue);
      expect(card(1).copyWith(autoTrackSince: () => null).tracksAutomatically, isFalse);
      expect(card(1).copyWith(archived: true).tracksAutomatically, isFalse);
      expect(card(1).walletApp, WalletApp.maya);
    });

    test('card columns round-trip', () {
      final c = PaymentCard.fromMap(card(3).toMap());
      expect(c.notifyApp, 'maya');
      expect(c.autoTrackSince, DateTime(2026, 11, 1));
    });
  });

  group('order payment status follows the money', () {
    BusinessOrder order({required int paid, int total = 50000, OrderStatus? status}) => BusinessOrder(
          buyer: 'Ana',
          orderDate: DateTime(2026, 11, 27),
          items: const [],
          total: total,
          paidAmount: paid,
          status: status,
          createdAt: DateTime(2026, 11, 27),
          updatedAt: DateTime(2026, 11, 27),
        );

    test('Unpaid, Partially Paid, Paid', () {
      expect(order(paid: 0).status, OrderStatus.unpaid);
      expect(order(paid: 20000).status, OrderStatus.partiallyPaid);
      expect(order(paid: 20000).balanceDue, 30000);
      expect(order(paid: 50000).status, OrderStatus.paid);
    });

    test('choosing Paid with less than the total stays Partially Paid', () {
      expect(order(paid: 20000, status: OrderStatus.paid).status, OrderStatus.partiallyPaid);
    });

    test('saved as complete / paid, read back the same', () {
      final partial = order(paid: 20000);
      expect(partial.toMap()['status'], 'complete');
      expect(BusinessOrder.fromMap({...partial.toMap(), 'id': 1}, const []).status, OrderStatus.partiallyPaid);
      expect(order(paid: 50000).toMap()['status'], 'paid');
    });

    test('fulfillment is separate and defaults to Pending', () {
      final o = order(paid: 0);
      expect(o.fulfillment, FulfillmentStatus.pending);
      final delivered = o.copyWith(fulfillment: FulfillmentStatus.delivered);
      expect(delivered.status, OrderStatus.unpaid);
      final back = BusinessOrder.fromMap({...delivered.toMap(), 'id': 1}, const []);
      expect(back.fulfillment, FulfillmentStatus.delivered);
      // Rows from before v12 have no fulfillment column.
      expect(BusinessOrder.fromMap({...o.toMap(), 'id': 1}..remove('fulfillment'), const []).fulfillment,
          FulfillmentStatus.pending);
    });
  });
}
