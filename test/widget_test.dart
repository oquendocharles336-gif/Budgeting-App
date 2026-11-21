// Replaces the default counter-app test from `flutter create`.
// Widget tests for full screens need a real SQLite database, so the main
// tests live in test/domain/. This one checks a shared widget renders.

import 'package:budgeting_app/domain/budget/budget_calculator.dart';
import 'package:budgeting_app/presentation/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EmptyState and BudgetProgressBar render', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              EmptyState(icon: Icons.inbox, title: 'Nothing here', message: 'Add something'),
              BudgetProgressBar(progress: BudgetProgress(budget: 1000, spent: 850)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add something'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
