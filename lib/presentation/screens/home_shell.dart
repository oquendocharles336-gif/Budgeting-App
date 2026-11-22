import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/sources/apk_updater.dart';
import '../../domain/services/photo_service.dart';
import '../../domain/services/update_service.dart';
import '../providers/app_state_providers.dart';
import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import '../theme/glass.dart';
import '../widgets/motion/animated_icons.dart';
import '../widgets/motion/cascade.dart';
import '../widgets/update_sheets.dart';
import 'budget/budget_screen.dart';
import 'business/business_shell.dart';
import 'business/inventory_screen.dart';
import 'business/products_screen.dart';
import 'cards/cards_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'transactions/transaction_form_screen.dart';
import 'transactions/transactions_screen.dart';

/// The tabs of the home screen.
enum HomeTab { home, activity, budget, wallets, business }

/// Icon and label of each tab in the bottom bar.
const _tabInfo = <HomeTab, ({IconData icon, String label, String semantics})>{
  HomeTab.home: (icon: Icons.home_rounded, label: 'Home', semantics: 'Home'),
  HomeTab.activity: (icon: Icons.receipt_long_rounded, label: 'Activity', semantics: 'Activity'),
  HomeTab.budget: (icon: Icons.pie_chart_rounded, label: 'Budget', semantics: 'Budget'),
  HomeTab.wallets: (icon: Icons.account_balance_wallet_rounded, label: 'Wallets', semantics: 'Wallets'),
  HomeTab.business: (icon: Icons.storefront_rounded, label: 'Business', semantics: 'Business'),
};

/// The tabs in bar order. The nav items, the pages and their indexes are
/// all built from this one list, so they always match. Business Mode adds
/// the Business tab at the end (so no other tab moves).
List<HomeTab> homeTabs({required bool business}) => [
      HomeTab.home,
      HomeTab.activity,
      HomeTab.budget,
      HomeTab.wallets,
      if (business) HomeTab.business,
    ];

/// Bottom navigation with a centered "+" button for quick add. Tabs switch
/// by tapping the bar (animated slide) or by swiping the page sideways.
///
/// Back button: screens pushed on top (add transaction, settings, ...)
/// close first, as usual. On a tab, back returns to the previously visited
/// tab, then to Home; on Home it asks before leaving the app.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  /// How many tabs sit left of the "+" button.
  static const leftCount = 2;

  /// Tab switch animation (taps and Back).
  static const switchDuration = Duration(milliseconds: 280);

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late List<HomeTab> _tabs;
  final PageController _pager = PageController();

  /// The selected tab. Only the bottom bar and the pages' ticker switches
  /// listen to it, so changing tabs never rebuilds the screens themselves.
  final ValueNotifier<HomeTab> _current = ValueNotifier(HomeTab.home);

  /// Tabs visited before the current one, oldest first.
  final List<HomeTab> _history = [];

  /// Each tab's page, made once and reused, so a rebuild of this shell
  /// (e.g. the "+" icon changing) doesn't rebuild every screen.
  final Map<HomeTab, Widget> _pages = {};

  /// True while the page moves because of a tap or Back (not a swipe):
  /// the pages it slides past must not change the selected tab.
  bool _programmatic = false;
  int _moveToken = 0;

  /// The "+" shows "×" while the add screen it opened is up.
  bool _adding = false;
  bool _exitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // The saved Business Mode, read before the first frame (no tab pop-in).
    _tabs = homeTabs(business: ref.read(businessModeProvider));
    // Start the work early: while Home is showing, load what the other
    // tabs will most likely need next, so they open with data ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetch();
      _startupFlow();
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _current.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Start-up: photo recovery, "What's new", update check
  // ---------------------------------------------------------------------------

  /// Photo recovery first (it may reopen a form), then "What's new", then
  /// the daily "newer version" check.
  Future<void> _startupFlow() async {
    await _recoverPhoto();
    await _showWhatsNew();
    await _checkForUpdate();
  }

  /// Shown once per version, after the first frame: for a new user, and
  /// after an update. It is marked as shown before it opens (so it can't
  /// open twice in this run, even after locking) and saved as seen when the
  /// user closes it.
  Future<void> _showWhatsNew() async {
    final updates = ref.read(updateServiceProvider);
    try {
      final entries = await updates.pendingWhatsNew();
      if (entries.isEmpty || !mounted) return;
      updates.markWhatsNewShown();
      await showWhatsNewSheet(context, entries);
      await updates.markWhatsNewSeen();
    } catch (e) {
      debugPrint('What\'s new failed: $e');
    }
  }

  Future<void> _checkForUpdate() async {
    // An APK downloaded for an update that is now installed isn't needed.
    await ApkUpdater.clearDownloads();
    if (!mounted) return;
    final updates = ref.read(updateServiceProvider);
    final check = await updates.checkIfDue(); // never throws; null when offline or not due
    if (check == null || check.status != UpdateStatus.available || !check.shouldPrompt || !mounted) return;
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
    ref.read(openDebtLoanCountsProvider.future).ignore();
  }

  Future<void> _openAdd() async {
    setState(() => _adding = true);
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TransactionFormScreen()),
    );
    if (mounted) setState(() => _adding = false);
  }

  // ---------------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------------

  /// A tap on the bar (or a shortcut on Home).
  void _go(HomeTab tab) => _show(tab, record: true);

  /// Slides to [tab]. Neighbours animate directly; for a far tab the pager
  /// first jumps next to it, so only one page slides in (the ones between
  /// are not built just to fly past).
  Future<void> _show(HomeTab tab, {required bool record}) async {
    final to = _tabs.indexOf(tab);
    final from = _current.value;
    if (to < 0 || tab == from) return;
    if (record && (_history.isEmpty || _history.last != from)) _history.add(from);
    _current.value = tab;
    if (!_pager.hasClients) return;

    final token = ++_moveToken;
    _programmatic = true;
    try {
      final page = _pager.page?.round() ?? _tabs.indexOf(from);
      if (Cascade.reduced(context)) {
        _pager.jumpToPage(to);
      } else {
        if ((to - page).abs() > 1) _pager.jumpToPage(to > page ? to - 1 : to + 1);
        await _pager.animateToPage(to, duration: HomeShell.switchDuration, curve: Curves.easeInOut);
      }
    } finally {
      if (token == _moveToken) {
        _programmatic = false;
        _syncToPage();
      }
    }
  }

  /// If a move was interrupted (e.g. by a drag), select the page that is
  /// actually showing.
  void _syncToPage() {
    if (!mounted || !_pager.hasClients) return;
    final i = _pager.page?.round();
    if (i == null || i < 0 || i >= _tabs.length) return;
    if (_tabs[i] != _current.value) _current.value = _tabs[i];
  }

  /// A swipe settled on page [i].
  void _onPageChanged(int i) {
    if (_programmatic || i < 0 || i >= _tabs.length) return;
    final tab = _tabs[i];
    final from = _current.value;
    if (tab == from) return;
    if (_history.isEmpty || _history.last != from) _history.add(from);
    _current.value = tab;
  }

  /// Business Mode switched in Settings: rebuild the tab list. If the
  /// Business tab was showing, go to Home first (jumpToPage(0)), so the
  /// pager never points past the last page.
  void _onBusinessModeChanged(bool on) {
    final next = homeTabs(business: on);
    if (listEquals(next, _tabs)) return;
    final current = _current.value;
    final stays = next.contains(current);
    _moveToken++; // cancels the bookkeeping of a move in progress
    _programmatic = true;
    try {
      if (!stays) {
        _current.value = HomeTab.home;
        if (_pager.hasClients) _pager.jumpToPage(0);
      } else {
        final i = next.indexOf(current);
        if (_pager.hasClients && _pager.page?.round() != i) _pager.jumpToPage(i);
      }
    } finally {
      _programmatic = false;
    }
    setState(() {
      _tabs = next;
      _history.removeWhere((t) => !next.contains(t));
      // Free a removed tab's screen; it's made again if the tab comes back.
      _pages.removeWhere((t, _) => !next.contains(t));
    });
  }

  /// Home's "Business" buttons: the tab when Business Mode is on,
  /// otherwise the business screens on top, as before.
  void _openBusiness() {
    if (_tabs.contains(HomeTab.business)) {
      _go(HomeTab.business);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessShell()));
    }
  }

  Widget _pageFor(HomeTab tab) => _pages.putIfAbsent(
        tab,
        () => _KeepAlivePage(
          key: ValueKey(tab),
          tab: tab,
          current: _current,
          // Entrance cascade once, when the tab is first built (on view).
          child: CascadeScope(
            child: switch (tab) {
              HomeTab.home => DashboardScreen(
                  onSeeAllTransactions: () => _go(HomeTab.activity),
                  onOpenBudget: () => _go(HomeTab.budget),
                  onOpenWallets: () => _go(HomeTab.wallets),
                  onOpenBusiness: _openBusiness,
                ),
              HomeTab.activity => const TransactionsScreen(),
              HomeTab.budget => const BudgetScreen(),
              HomeTab.wallets => const CardsScreen(asTab: true),
              HomeTab.business => const BusinessShell(asTab: true),
            },
          ),
        ),
      );

  Future<void> _onBack() async {
    if (_current.value != HomeTab.home) {
      var previous = HomeTab.home;
      // Skip entries equal to the tab we're leaving, or no longer shown.
      while (_history.isNotEmpty) {
        final last = _history.removeLast();
        if (last != _current.value && _tabs.contains(last)) {
          previous = last;
          break;
        }
      }
      await _show(previous, record: false);
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
    // Not watched: a change is handled once, before the next frame, so the
    // pager is moved before it gets a shorter list.
    ref.listen<bool>(businessModeProvider, (_, on) => _onBusinessModeChanged(on));

    final tabs = _tabs;
    // Only this route's own back press reaches here: a pushed screen on top
    // is its own route and pops normally before any tab logic applies.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        // Swipe left / right between tabs. Clamping: no bounce past the
        // first and last tab. A swipe that starts on something that slides
        // itself (a transaction row, the card deck, a chip row) belongs to
        // that widget; anywhere else it changes tab.
        body: PageView.builder(
          controller: _pager,
          physics: const ClampingScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemCount: tabs.length,
          itemBuilder: (context, i) => _pageFor(tabs[i]),
          // Pages are keyed by tab, so a page keeps its state when the
          // list changes (Business Mode on/off).
          findChildIndexCallback: (key) {
            if (key is! ValueKey<HomeTab>) return null;
            final i = tabs.indexOf(key.value);
            return i < 0 ? null : i;
          },
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
          // Clips the frosted bar to the notched shape.
          clipBehavior: Clip.antiAlias,
          child: GlassBar(
            child: ValueListenableBuilder<HomeTab>(
              valueListenable: _current,
              builder: (context, current, _) {
                Widget item(HomeTab t) => _NavItem(
                      icon: _tabInfo[t]!.icon,
                      label: _tabInfo[t]!.label,
                      semanticsLabel: _tabInfo[t]!.semantics,
                      selected: t == current,
                      onTap: () => _go(t),
                    );
                final left = tabs.take(HomeShell.leftCount).toList();
                final right = tabs.skip(HomeShell.leftCount).toList();
                // Two equal halves keep the gap centred under the "+",
                // whatever the number of tabs on each side.
                return Row(
                  children: [
                    Expanded(child: Row(children: [for (final t in left) item(t)])),
                    const SizedBox(width: 72),
                    Expanded(child: Row(children: [for (final t in right) item(t)])),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab alive in the pager (state, scroll position and loaded data
/// survive swiping away), and pauses its animations while it isn't the
/// selected tab.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.tab, required this.current, required this.child});
  final HomeTab tab;
  final ValueListenable<HomeTab> current;
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Only TickerMode rebuilds on a tab change; the screen ([child]) is
    // the same widget, so it isn't rebuilt.
    return ValueListenableBuilder<HomeTab>(
      valueListenable: widget.current,
      builder: (context, current, child) => TickerMode(enabled: current == widget.tab, child: child!),
      child: widget.child,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String semanticsLabel;
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
        label: semanticsLabel,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Scales down instead of overflowing on narrow phones.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: selected ? scheme.onPrimaryContainer : color),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
