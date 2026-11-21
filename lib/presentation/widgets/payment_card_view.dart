import 'package:flutter/material.dart';

import '../../data/models/payment_card.dart';
import '../theme/app_theme.dart';

/// A small visual "plastic card".
class PaymentCardView extends StatelessWidget {
  const PaymentCardView({super.key, required this.card, this.onTap, this.width = 220, this.subtitle});

  final PaymentCard card;
  final VoidCallback? onTap;
  final double width;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final base = Color(card.color);
    final hsl = HSLColor.fromColor(base);
    final end = hsl.withLightness((hsl.lightness * 0.6).clamp(0.05, 1.0).toDouble()).toColor();
    final fg = AppTheme.onColor(base);
    return Semantics(
      button: onTap != null,
      label: '${card.nickname}, ${card.type.label} card ending ${card.last4}',
      child: SizedBox(
        width: width,
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
                      Text(
                        '••••  ${card.last4}',
                        style: TextStyle(color: fg, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle ?? card.type.label,
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
