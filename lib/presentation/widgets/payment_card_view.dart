import 'package:material_ui/material_ui.dart';

import '../../data/models/payment_card.dart';
import '../theme/app_theme.dart';

/// A small visual "plastic card".
class PaymentCardView extends StatefulWidget {
  const PaymentCardView({
    super.key,
    required this.card,
    this.onTap,
    this.width = 220,
    this.subtitle,
    this.allowReveal = false,
  });

  final PaymentCard card;
  final VoidCallback? onTap;
  final double width;
  final String? subtitle;

  /// Shows an eye button that reveals an e-wallet's full mobile number.
  final bool allowReveal;

  @override
  State<PaymentCardView> createState() => _PaymentCardViewState();
}

class _PaymentCardViewState extends State<PaymentCardView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final onTap = widget.onTap;
    final canReveal = widget.allowReveal && card.hasMobileNumber;
    final number = canReveal && _revealed ? card.mobileNumber! : card.maskedNumber;
    final base = Color(card.color);
    final hsl = HSLColor.fromColor(base);
    final end = hsl.withLightness((hsl.lightness * 0.6).clamp(0.05, 1.0).toDouble()).toColor();
    final fg = AppTheme.onColor(base);
    return Semantics(
      button: onTap != null,
      // Screen readers get the same last 3 digits the mask shows, never the full number.
      label: card.hasMobileNumber && card.mobileNumber!.length >= 3
          ? '${card.nickname}, ${card.type.label}, number ending ${card.mobileNumber!.substring(card.mobileNumber!.length - 3)}'
          : '${card.nickname}, ${card.type.label} card ending ${card.last4}',
      child: SizedBox(
        width: widget.width,
        child: AspectRatio(
          aspectRatio: 1.6,
          child: Material(
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [base, end], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              card.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          Icon(
                            card.type == CardType.ewallet ? Icons.account_balance_wallet_rounded : Icons.contactless_rounded,
                            color: fg.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              number,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (canReveal)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: _revealed ? 'Hide number' : 'Show number',
                              color: fg,
                              icon: Icon(_revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                              onPressed: () => setState(() => _revealed = !_revealed),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle ?? card.type.label,
                        style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
