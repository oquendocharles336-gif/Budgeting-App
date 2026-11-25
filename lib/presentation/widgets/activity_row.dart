import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/category.dart';
import '../../data/models/payment_card.dart';
import '../../data/models/transaction_entry.dart';
import '../providers/core_providers.dart';
import '../screens/transactions/transaction_form_screen.dart';
import '../theme/app_palette.dart';
import '../theme/glass.dart';
import 'common.dart';
import 'motion/cascade.dart';
import 'transaction_tile.dart';

/// Which row of a list is floating (tapped) or has its actions open
/// (swiped). One per list; at most one row of each at a time.
class ActivitySelection extends ChangeNotifier {
  int? _floating;
  int? _revealed;

  int? get floating => _floating;
  int? get revealed => _revealed;

  /// Tap: float this row (or put it back if it already floats).
  void toggleFloat(int id) {
    _floating = _floating == id ? null : id;
    _revealed = null;
    notifyListeners();
  }

  /// Swipe: show this row's Edit / Delete (null hides them).
  void reveal(int? id) {
    if (_revealed == id && (id == null || _floating == null)) return;
    _revealed = id;
    if (id != null) _floating = null;
    notifyListeners();
  }

  /// Tap anywhere else: everything goes back.
  void closeAll() {
    if (_floating == null && _revealed == null) return;
    _floating = null;
    _revealed = null;
    notifyListeners();
  }
}

/// A transaction in "Recent transactions" and Activity.
///
///  * Tap: the row floats (raised, slightly bigger glass card) and shows its
///    details (full description, notes, date and time, paid with).
///  * Swipe right: Edit and Delete appear on the left. Delete asks first.
///  * Tap anywhere else: the floating card / actions close.
///
/// Rows still being saved (optimistic, negative id) just show the tile.
class ActivityRow extends ConsumerStatefulWidget {
  const ActivityRow({
    super.key,
    required this.tx,
    required this.selection,
    required this.category,
    required this.card,
    this.toCard,
    this.showDate = true,
    this.onDeleted,
  });

  final TransactionEntry tx;
  final ActivitySelection selection;
  final Category? category;
  final PaymentCard? card;
  final PaymentCard? toCard;
  final bool showDate;

  /// Called after the row was deleted (e.g. to hide it from the list at once).
  final VoidCallback? onDeleted;

  @override
  ConsumerState<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends ConsumerState<ActivityRow> with SingleTickerProviderStateMixin {
  static const _actionsWidth = 168.0;
  static const _motion = Duration(milliseconds: 240);

  late final AnimationController _slide = AnimationController(vsync: this, duration: _motion);
  bool _dragging = false;

  int get _id => widget.tx.id ?? 0;
  bool get _saved => (widget.tx.id ?? -1) > 0;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelection);
  }

  @override
  void didUpdateWidget(ActivityRow old) {
    super.didUpdateWidget(old);
    if (old.selection != widget.selection) {
      old.selection.removeListener(_onSelection);
      widget.selection.addListener(_onSelection);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelection);
    _slide.dispose();
    super.dispose();
  }

  void _onSelection() {
    if (!mounted) return;
    if (!_dragging) _settle(widget.selection.revealed == _id);
    setState(() {});
  }

  void _settle(bool open) {
    final target = open ? 1.0 : 0.0;
    if (_slide.value == target) return;
    if (Cascade.reduced(context)) {
      _slide.value = target;
    } else {
      _slide.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _onDragStart(DragStartDetails _) {
    _dragging = true;
    if (widget.selection.floating != null) widget.selection.closeAll();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _slide.value = (_slide.value + d.primaryDelta! / _actionsWidth).clamp(0.0, 1.0).toDouble();
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.primaryVelocity ?? 0;
    // A flick decides; otherwise past halfway opens.
    final open = v.abs() > 300 ? v > 0 : _slide.value > 0.5;
    widget.selection.reveal(open ? _id : (widget.selection.revealed == _id ? null : widget.selection.revealed));
    _settle(open);
  }

  void _onTap() {
    if (widget.selection.revealed == _id) {
      widget.selection.reveal(null);
      return;
    }
    widget.selection.toggleFloat(_id);
  }

  Future<void> _edit() async {
    widget.selection.closeAll();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionFormScreen(existing: widget.tx)));
  }

  Future<void> _delete() async {
    final t = widget.tx;
    final extra = t.isTransfer && !t.isCapitalTransfer
        ? ' Its fee, if any, is deleted too.'
        : (t.isLoanPayment ? ' The loan is marked unpaid again.' : '');
    final ok = await confirm(
      context,
      title: 'Delete transaction?',
      message: '"${t.description}" will be removed and the money returned to its account.$extra This can\'t be undone.',
    );
    if (!ok || !mounted) return;
    widget.selection.closeAll();
    try {
      await ref.read(transactionServiceProvider).delete(t.id!);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete: $e', error: true);
      return;
    }
    widget.onDeleted?.call();
    // Budget, balances, Insights and every list refresh.
    ref.refreshData();
    if (mounted) showSnack(context, 'Transaction deleted');
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final tile = TransactionTile(
      tx: tx,
      category: widget.category,
      card: widget.card,
      toCard: widget.toCard,
      showDate: widget.showDate,
      onTap: _saved ? _onTap : null,
    );
    if (!_saved) return tile;

    final t = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final floating = widget.selection.floating == _id;
    final open = widget.selection.revealed == _id;
    final reduced = Cascade.reduced(context);
    final motion = reduced ? Duration.zero : _motion;

    final foreground = AnimatedScale(
      scale: floating ? 1.03 : 1,
      duration: motion,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: motion,
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(horizontal: floating ? 6 : 0, vertical: floating ? 6 : 0),
        decoration: BoxDecoration(
          color: floating ? Glass.fill(t, strong: true) : Colors.transparent,
          borderRadius: BorderRadius.circular(Glass.radius),
          border: Border.all(color: floating ? Glass.border(t) : Colors.transparent),
          boxShadow: floating ? Glass.shadow(t, lift: 1) : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(Glass.radius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile,
              AnimatedSize(
                duration: motion,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: floating ? _Details(row: widget) : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );

    return TapRegion(
      groupId: widget.selection,
      // Tapping outside every row of this list closes the floating card.
      onTapOutside: floating || open ? (_) => widget.selection.closeAll() : null,
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Edit'): _edit,
          const CustomSemanticsAction(label: 'Delete'): _delete,
        },
        child: Stack(
          children: [
            // Actions behind the row, revealed by swiping right.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _slide,
                builder: (context, child) => IgnorePointer(
                  ignoring: _slide.value < 0.5,
                  child: Opacity(opacity: _slide.value, child: child),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: _actionsWidth,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.edit_rounded,
                            label: 'Edit',
                            background: scheme.primaryContainer,
                            foreground: scheme.onPrimaryContainer,
                            onTap: _edit,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.delete_rounded,
                            label: 'Delete',
                            background: scheme.errorContainer,
                            foreground: scheme.onErrorContainer,
                            onTap: _delete,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: AnimatedBuilder(
                animation: _slide,
                builder: (context, child) => Transform.translate(offset: Offset(_slide.value * _actionsWidth, 0), child: child),
                child: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.background, required this.foreground, required this.onTap});
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What the floating card reveals.
class _Details extends StatelessWidget {
  const _Details({required this.row});
  final ActivityRow row;

  @override
  Widget build(BuildContext context) {
    final tx = row.tx;
    final t = context.tokens;
    final muted = TextStyle(color: t.onSecondMuted, fontSize: 13);
    String account(int? id, PaymentCard? c) => id == null ? 'Cash' : (c?.shortLabel ?? 'Card');
    final lines = <(IconData, String)>[
      (Icons.event_rounded, DateFormat('EEEE, MMMM d, yyyy · h:mm a').format(tx.date)),
      if (tx.isTransfer)
        (
        Icons.swap_horiz_rounded,
        '${tx.fromCapital ? 'Business capital' : account(tx.cardId, row.card)} → '
            '${tx.toCapital ? 'Business capital' : account(tx.toCardId, row.toCard)}',
        )
      else
        (
        tx.cardId == null ? Icons.payments_rounded : Icons.account_balance_wallet_rounded,
        '${tx.isIncome ? 'Received in' : 'Paid with'} ${account(tx.cardId, row.card)}',
        ),
      if (!tx.isTransfer)
        (
        Icons.category_rounded,
        (tx.customCategory?.trim().isNotEmpty ?? false) ? tx.customCategory!.trim() : (row.category?.name ?? 'Uncategorized'),
        ),
      if (tx.isLoanCancelledByRepayment)
        (
        Icons.check_circle_rounded,
        'Not counted in ${DateFormat('MMMM').format(tx.date)}\'s budget — repaid ${DateFormat('MMM d').format(tx.loanPaidAt!)}',
        )
      else if (tx.isExpense)
        (Icons.pie_chart_rounded, 'Counted in ${DateFormat('MMMM').format(tx.date)}\'s budget'),
      if (tx.isLoanPaid && !tx.isLoanCancelledByRepayment)
        (Icons.check_circle_rounded, 'Loan paid ${DateFormat('MMM d').format(tx.loanPaidAt!)}${tx.loanPaidMethod == null ? '' : ' · ${tx.loanPaidMethod!.label}'}'),
      if (tx.isLoanPayment)
        (Icons.link_rounded, tx.isIncome ? 'Repayment of a loan you gave' : 'Payment of a loan you received'),
      if (tx.source != TransactionSourceType.manual) (Icons.file_download_rounded, 'Imported from ${tx.source.label}'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx.description, style: TextStyle(color: t.onSecond, fontWeight: FontWeight.w600)),
          if (tx.notes != null && tx.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(tx.notes!.trim(), style: TextStyle(color: t.onSecond)),
          ],
          const SizedBox(height: 8),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Builder(builder: (context) {
                // A loan that came back the same month is called out in green.
                final good = tx.isLoanCancelledByRepayment && text.startsWith('Not counted');
                final color = good ? t.success : t.onSecondMuted;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Icon(icon, size: 16, color: color)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text, style: good ? muted.copyWith(color: color, fontWeight: FontWeight.w600) : muted),
                    ),
                  ],
                );
              }),
            ),
          const SizedBox(height: 4),
          Text('Swipe right to edit or delete', style: muted.copyWith(fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}