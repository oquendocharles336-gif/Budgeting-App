import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../loans/loans_screen.dart';
import 'debt_form_screen.dart';
import 'debts_screen.dart';

/// Which list the "Debts" tab shows.
enum DebtsSection { debts, loans }

class DebtsSectionController extends Notifier<DebtsSection> {
  @override
  DebtsSection build() => DebtsSection.debts;

  void show(DebtsSection section) => state = section;
}

/// Lets Home ("Debts" / "Loans" buttons) open the tab on the right list.
final debtsSectionProvider = NotifierProvider<DebtsSectionController, DebtsSection>(DebtsSectionController.new);

/// The "Debts" tab: debts you owe and "Loan" transactions, switched with a
/// segmented button. A button (not a swipe) on purpose: the tabs of the
/// home screen already switch with a horizontal swipe.
class DebtsLoansScreen extends ConsumerWidget {
  const DebtsLoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(debtsSectionProvider);
    // Only the two numbers; the lists below watch their own data.
    final counts = ref.watch(openDebtLoanCountsProvider.select((a) => a.asDataOrNull ?? const OpenDebtLoanCounts()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debts & Loans'),
        actions: [
          if (section == DebtsSection.debts)
            IconButton(
              tooltip: 'Add debt',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebtFormScreen())),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<DebtsSection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: DebtsSection.debts,
                    icon: const Icon(Icons.handshake_rounded),
                    label: Text(counts.debts > 0 ? 'Debts (${_short(counts.debts)})' : 'Debts'),
                  ),
                  ButtonSegment(
                    value: DebtsSection.loans,
                    icon: const Icon(Icons.request_quote_rounded),
                    label: Text(counts.loans > 0 ? 'Loans (${_short(counts.loans)})' : 'Loans'),
                  ),
                ],
                selected: {section},
                onSelectionChanged: (s) => ref.read(debtsSectionProvider.notifier).show(s.first),
              ),
            ),
          ),
        ),
      ),
      // Both lists stay mounted (scroll position kept when switching); the
      // hidden one has its animations paused.
      body: IndexedStack(
        index: section.index,
        children: [
          TickerMode(enabled: section == DebtsSection.debts, child: const DebtsScreen(asTab: true)),
          TickerMode(enabled: section == DebtsSection.loans, child: const LoansScreen(asTab: true)),
        ],
      ),
    );
  }

  static String _short(int n) => n > 99 ? '99+' : '$n';
}
