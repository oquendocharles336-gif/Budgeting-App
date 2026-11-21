/// The payment counter: what the buyer handed over against what they owe.
///
/// Example: total 120, buyer hands over 500 cash -> applied 120, change 380.
class PaymentResult {
  const PaymentResult({
    required this.due,
    required this.tendered,
    required this.applied,
    required this.change,
    required this.remaining,
  });

  /// Still owed before this payment.
  final int due;

  /// What the buyer handed over.
  final int tendered;

  /// What counts toward the order (never more than [due]).
  final int applied;

  /// What to give back.
  final int change;

  /// Still owed after this payment (partial payment).
  final int remaining;

  /// The buyer handed over less than they owe.
  bool get isShort => tendered < due;
  bool get isPartial => applied > 0 && remaining > 0;
  bool get settles => due > 0 && remaining == 0;
}

class PaymentCalculator {
  PaymentCalculator._();

  /// All amounts in centavos. Throws [ArgumentError] for negative input.
  static PaymentResult compute({required int total, int alreadyPaid = 0, required int tendered}) {
    if (total < 0 || alreadyPaid < 0 || tendered < 0) {
      throw ArgumentError('Amounts can\'t be negative');
    }
    final due = total - alreadyPaid > 0 ? total - alreadyPaid : 0;
    final applied = tendered < due ? tendered : due;
    return PaymentResult(
      due: due,
      tendered: tendered,
      applied: applied,
      change: tendered - applied,
      remaining: due - applied,
    );
  }
}
