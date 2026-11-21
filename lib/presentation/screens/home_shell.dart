import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../domain/services/photo_service.dart';
import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import '../widgets/motion/animated_icons.dart';
import '../widgets/motion/cascade.dart';
import '../widgets/update_sheets.dart';
import 'budget/budget_screen.dart';
import 'business/inventory_screen.dart';
import 'business/products_screen.dart';
import 'cards/cards_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'transactions/transaction_form_screen.dart';
import 'transactions/transactions_screen.dart';

/// Bottom navigation with a centered "+" button for quick add.
///
/// Back button: screens pushed on top (add transaction, settings, ...)
/// close first, as usual. On a tab, back returns to the previously visited
/// tab, then to Home; on Home it asks before leaving the app.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const home = 0;
  static const activity = 1;
  static const budget = 2;
  static const wallets = 3;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = HomeShell.home;

  /// Tabs are built the first time they're opened, so their list
  /// entrance plays when the user actually sees it.
  final Set<int> _built = {HomeShell.home};

  /// The "+" shows "×" while the add screen it opened is up.
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Start the work early: while Home is showing, load what the other
    // tabs will most likely need next, so they open with data ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetch();
      _startupFlow();
    });
  }

  /// Photo recovery first (it may reopen a form), then "What's new" after
  /// an update, then the daily "newer version" check.
  Future<void> _startupFlow() async {
    await _recoverPhoto();
    await _showWhatsNew();
    await _checkForUpdate();
  }

  Future<void> _showWhatsNew() async {
    try {
      final updates = ref.read(updateServiceProvider);
      final hasData = (await ref.read(transactionRepositoryProvider).recent(limit: 1)).isNotEmpty ||
          (await ref.read(cardRepositoryProvider).all()).isNotEmpty;
      final entries = await updates.pendingWhatsNew(hasExistingData: hasData);
      if (entries.isEmpty || !mounted) return;
      await showWhatsNewSheet(context, entries);
      await updates.markWhatsNewSeen((await updates.installed()).build);
    } catch (e) {
      debugPrint('What\'s new failed: $e');
    }
  }

  Future<void> _checkForUpdate() async {
    final updates = ref.read(updateServiceProvider);
    final check = await updates.checkIfDue(); // never throws
    if (check == null || !check.shouldPrompt || !mounted) return;
    await showUpdateSheet(context, check: check, onSkip: updates.skip);
  }

  /// Android may close the app while the camera is open (low memory). If
  /// that happened, reopen the form that was being filled in, with the
  /// photo (ImagePicker.retrieveLostData) and what was typed.
  Future<void> _recoverPhoto() async {
    final RecoveredForm? r;
    try {
      r = await ref.read(photoServiceProvider).recoverLost();
    } catch (e) {
      debugPrint('Photo recovery failed: $e');
      return;
    }
    if (r == null || !mounted) return;
    final photos = ref.read(photoServiceProvider);
    final draft = r.draft;
    final taken = photos.takeRecovery(draft.form, draft.recordId);
    if (taken == null) return;
    Widget? form;
    try {
      if (draft.form == PhotoDraft.inventoryForm) {
        final existing = draft.recordId == null ? null : await ref.read(inventoryRepositoryProvider).byId(draft.recordId!);
        form = InventoryFormScreen(existing: existing, recovered: taken);
      } else if (draft.form == PhotoDraft.productForm) {
        final products = await ref.read(productRepositoryProvider).all();
        final existing = products.where((p) => p.id == draft.recordId).firstOrNull;
        form = ProductFormScreen(existing: existing, recovered: taken);
      }
    } catch (e) {
      debugPrint('Could not reopen the form: $e');
    }
    if (form == null || !mounted) return;
    final page = form;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _prefetch() {
    if (!mounted) return;
    final now = DateTime.now();
    final thisMonth = Dates.monthKey(now);
    final lastMonth = Dates.monthKey(Dates.previousMonth(Dates.monthStart(now)));
    // Results are cached in the providers; errors show on the screen later.
    ref.read(analyticsProvider(thisMonth).future).ignore();
    ref.read(monthSummaryProvider(lastMonth).future).ignore();
    ref.read(budgetHistoryProvider.future).ignore();
    ref.read(filteredTransactionsProvider.future).ignore();
    ref.read(balanceSummaryProvider.future).ignore();
    ref.read(debtsProvider.future).ignore();
  }

  Future<void> _openAdd() async {
    setState(() => _adding = true);
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TransactionFormScreen()),
    );
    if (mounted) setState(() => _adding = false);
  }

  /// Tabs visited before the current one, oldest first.
  final List<int> _history = [];
  bool _exitDialogOpen = false;

  void _go(int i) {
    if (i == _index) return;
    setState(() {
      // No duplicate consecutive entries.
      if (_history.isEmpty || _history.last != _index) _history.add(_index);
      _index = i;
      _built.add(i);
    });
  }

  Future<void> _onBack() async {
    if (_index != HomeShell.home) {
      setState(() {
        var previous = HomeShell.home;
        // Skip entries equal to the tab we're leaving.
        while (_history.isNotEmpty) {
          final last = _history.removeLast();
          if (last != _index) {
            previous = last;
            break;
          }
        }
        _index = previous;
        _built.add(previous);
      });
      return;
    }
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit app?'),
        content: const Text('Are you sure you want to exit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (exit ?? false) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        onSeeAllTransactions: () => _go(HomeShell.activity),
        onOpenBudget: () => _go(HomeShell.budget),
        onOpenWallets: () => _go(HomeShell.wallets),
      ),
      const TransactionsScreen(),
      const BudgetScreen(),
      const CardsScreen(asTab: true),
    ];
    // Only this route's own back press reaches here: a pushed screen on top
    // is its own route and pops normally before any tab logic applies.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < pages.length; i++)
              _built.contains(i) ? CascadeScope(child: pages[i]) : const SizedBox.shrink(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add transaction',
          // Round so it sits in the CircularNotchedRectangle notch.
          shape: const CircleBorder(),
          onPressed: _adding ? null : _openAdd,
          child: AnimatedPlusIcon(open: _adding),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          height: 68,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: _index == HomeShell.home,
                onTap: () => _go(HomeShell.home),
              ),
              _NavItem(
                icon: Icons.receipt_long_rounded,
                label: 'Activity',
                selected: _index == HomeShell.activity,
                onTap: () => _go(HomeShell.activity),
              ),
              const SizedBox(width: 72),
              _NavItem(
                icon: Icons.pie_chart_rounded,
                label: 'Budget',
                selected: _index == HomeShell.budget,
                onTap: () => _go(HomeShell.budget),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Wallets',
                selected: _index == HomeShell.wallets,
                onTap: () => _go(HomeShell.wallets),
              ),
            ],
          ),
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
