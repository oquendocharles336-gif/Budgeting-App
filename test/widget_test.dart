// Replaces the default counter-app test from `flutter create`.
// Widget tests for full screens need a real SQLite database, so the main
// tests live in test/domain/. This one checks a shared widget renders.

import 'package:budgeting_app/domain/budget/budget_calculator.dart';
import 'package:budgeting_app/presentation/theme/app_palette.dart';
import 'package:budgeting_app/presentation/theme/app_theme.dart';
import 'package:budgeting_app/presentation/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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

  testWidgets('Shared widgets also render inside the app theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AppPalettes.sunsetOrange),
        darkTheme: AppTheme.dark(AppPalettes.sunsetOrange),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: BudgetProgressBar(progress: BudgetProgress(budget: 1000, spent: 1200)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
