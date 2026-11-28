import 'package:budgeting_app/domain/business/payment_calculator.dart';
import 'package:budgeting_app/presentation/providers/core_providers.dart';
import 'package:budgeting_app/presentation/screens/business/collect_payment_sheet.dart';
import 'package:budgeting_app/presentation/screens/business/order_form_screen.dart';
import 'package:budgeting_app/presentation/theme/app_palette.dart';
import 'package:budgeting_app/presentation/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Quick Pay - Payment Calculator & Quick Amounts', () {
    test('Exact payment produces zero change and isExact = true', () {
      final res = PaymentCalculator.compute(total: 25000, tendered: 25000);
      expect(res.due, 25000);
      expect(res.tendered, 25000);
      expect(res.applied, 25000);
      expect(res.change, 0);
      expect(res.remaining, 0);
      expect(res.isShort, isFalse);
      expect(res.isExact, isTrue);
      expect(res.isOver, isFalse);
    });

    test('Overpayment calculates change and isOver = true', () {
      final res = PaymentCalculator.compute(total: 25000, tendered: 50000);
      expect(res.due, 25000);
      expect(res.tendered, 50000);
      expect(res.applied, 25000);
      expect(res.change, 25000);
      expect(res.remaining, 0);
      expect(res.isShort, isFalse);
      expect(res.isExact, isFalse);
      expect(res.isOver, isTrue);
    });

    test('Underpayment calculates remaining balance and isShort = true', () {
      final res = PaymentCalculator.compute(total: 25000, tendered: 10000);
      expect(res.due, 25000);
      expect(res.tendered, 10000);
      expect(res.applied, 10000);
      expect(res.change, 0);
      expect(res.remaining, 15000);
      expect(res.isShort, isTrue);
      expect(res.isExact, isFalse);
      expect(res.isOver, isFalse);
    });

    test('Quick Amount chips generates exact amount and bill denominations', () {
      // For 150 pesos balance due (15000 centavos)
      final chips = getQuickAmountChips(15000);
      expect(chips, equals([15000, 20000, 50000, 100000]));
    });
  });

  group('Quick Pay - PaymentChangeLine Widget', () {
    Widget buildWidget(PaymentResult result, {bool cash = true}) {
      return ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light(AppPalettes.sunsetOrange),
          home: Scaffold(
            body: PaymentChangeLine(result: result, cash: cash),
          ),
        ),
      );
    }

    testWidgets('renders Change Due for cash overpayment', (tester) async {
      final res = PaymentCalculator.compute(total: 10000, tendered: 50000);
      await tester.pumpWidget(buildWidget(res, cash: true));
      expect(find.text('Change Due'), findsOneWidget);
      expect(find.text('Give back to buyer'), findsOneWidget);
      expect(find.text('₱400.00'), findsOneWidget);
    });

    testWidgets('renders Exact Amount for exact payment', (tester) async {
      final res = PaymentCalculator.compute(total: 10000, tendered: 10000);
      await tester.pumpWidget(buildWidget(res, cash: true));
      expect(find.text('Exact Amount'), findsOneWidget);
    });

    testWidgets('renders Shortage / Insufficient for underpayment', (tester) async {
      final res = PaymentCalculator.compute(total: 10000, tendered: 5000);
      await tester.pumpWidget(buildWidget(res, cash: true));
      expect(find.textContaining('Shortage / Insufficient'), findsOneWidget);
      expect(find.textContaining('₱50.00 balance left'), findsOneWidget);
    });
  });
}
