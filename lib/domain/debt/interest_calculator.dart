import 'dart:math' as math;

import '../../data/models/debt.dart';

/// What to get ready for a debt this month. Amounts are in centavos and
/// are estimates: the lender's statement always wins.
class InterestQuote {
  const InterestQuote({
    required this.monthlyRate,
    required this.interestThisMonth,
    required this.dueThisMonth,
    this.monthlyPayment,
    this.totalInterest,
  });

  /// As a fraction: 0.03 = 3% a month.
  final double monthlyRate;

  /// Interest for one month.
  final int interestThisMonth;

  /// Full monthly payment (principal + interest), when a term is set.
  final int? monthlyPayment;

  /// Interest over the whole term, when a term is set.
  final int? totalInterest;

  /// The amount to prepare this month: the monthly payment if a term is
  /// set, otherwise just the interest (the least to pay so the debt
  /// doesn't grow). Never more than what's left plus this month's interest.
  final int dueThisMonth;
}

class InterestCalculator {
  InterestCalculator._();

  /// A yearly rate is treated as nominal (divided by 12), the way banks
  /// quote loans that are charged monthly.
  static double monthlyRate(int rateBp, InterestPeriod period) {
    final r = rateBp / 10000;
    return period == InterestPeriod.month ? r : r / 12;
  }

  /// [principal] is the amount borrowed; [remaining] is what's still owed.
  ///
  /// * Simple: interest every month = principal x monthly rate. With a term,
  ///   monthly payment = principal / months + that interest (add-on loans).
  /// * Compound: interest this month = remaining x monthly rate, so it falls
  ///   as you pay. With a term, the monthly payment is the standard
  ///   amortized amount: P x r / (1 - (1 + r)^-n).
  ///
  /// Returns null when there's no rate and no term to work with.
  static InterestQuote? quote({
    required int principal,
    required int remaining,
    int? rateBp,
    InterestType type = InterestType.simple,
    InterestPeriod period = InterestPeriod.month,
    int? termMonths,
  }) {
    final hasRate = rateBp != null && rateBp > 0;
    final n = (termMonths != null && termMonths > 0) ? termMonths : null;
    if (!hasRate && n == null) return null;
    if (principal <= 0 || remaining <= 0) {
      return InterestQuote(monthlyRate: hasRate ? monthlyRate(rateBp, period) : 0, interestThisMonth: 0, dueThisMonth: 0);
    }
    final r = hasRate ? monthlyRate(rateBp, period) : 0.0;

    final int interest;
    int? payment;
    int? total;
    switch (type) {
      case InterestType.simple:
        interest = (principal * r).round();
        if (n != null) {
          payment = (principal / n + principal * r).round();
          total = (principal * r * n).round();
        }
      case InterestType.compound:
        interest = (remaining * r).round();
        if (n != null) {
          final exact = r == 0 ? principal / n : principal * r / (1 - math.pow(1 + r, -n));
          payment = exact.round();
          total = (exact * n - principal).round();
        }
    }

    final cap = remaining + interest;
    return InterestQuote(
      monthlyRate: r,
      interestThisMonth: interest,
      monthlyPayment: payment,
      totalInterest: total,
      dueThisMonth: math.min(payment ?? interest, cap),
    );
  }

  static InterestQuote? forStatus(DebtStatus s) {
    if (s.isSettled) return null;
    final d = s.debt;
    return quote(
      principal: d.totalAmount,
      remaining: s.remaining,
      rateBp: d.interestRateBp,
      type: d.interestType,
      period: d.interestPeriod,
      termMonths: d.termMonths,
    );
  }
}
