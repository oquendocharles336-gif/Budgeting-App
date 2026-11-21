import 'package:flutter/material.dart';

import 'analytics/analytics_screen.dart';
import 'budget/budget_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'transactions/transaction_form_screen.dart';
import 'transactions/transactions_screen.dart';

/// Bottom navigation with a centered "+" button for quick add.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onSeeAllTransactions: () => _go(1), onOpenBudget: () => _go(2)),
      const TransactionsScreen(),
      const BudgetScreen(),
      const AnalyticsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add transaction',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TransactionFormScreen()),
        ),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _NavItem(icon: Icons.home_rounded, label: 'Home', selected: _index == 0, onTap: () => _go(0)),
            _NavItem(icon: Icons.receipt_long_rounded, label: 'Activity', selected: _index == 1, onTap: () => _go(1)),
            const SizedBox(width: 72),
            _NavItem(icon: Icons.pie_chart_rounded, label: 'Budget', selected: _index == 2, onTap: () => _go(2)),
            _NavItem(icon: Icons.insights_rounded, label: 'Insights', selected: _index == 3, onTap: () => _go(3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: selected ? scheme.onPrimaryContainer : color),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
