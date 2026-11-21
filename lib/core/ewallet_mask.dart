/// Display helpers for e-wallet (GCash, Maya, ...) mobile numbers.
///
/// The full number stays in the database; these are for showing it only.
library;

/// Shortest number we mask. Shorter input is returned as-is because
/// keeping 2 + 3 characters would leave almost nothing hidden.
const int minMaskableLength = 7;

/// Removes spaces, dashes, dots and brackets, and turns the Philippine
/// country code into a leading 0:
///   "(+63) 912 345 6768" -> "09123456768"
///   "+639123456768"      -> "09123456768"
///   "639123456768"       -> "09123456768"
String normalizePhMobileNumber(String input) {
  var n = input.replaceAll(RegExp(r'[\s\-.()]'), '');
  if (n.startsWith('+63')) {
    n = '0${n.substring(3)}';
  } else if (n.startsWith('63') && n.length == 12) {
    n = '0${n.substring(2)}';
  }
  return n;
}

/// Masks an e-wallet number for display: first 2 and last 3 characters
/// are kept and everything in between becomes "*".
///
///   maskEWalletNumber('09123456768')        -> '09******768'
///   maskEWalletNumber('(+63) 912-345-6768') -> '09******768'
///
/// Returns [number] unchanged if, after normalizing, it is too short to
/// mask safely (fewer than [minMaskableLength] characters).
String maskEWalletNumber(String number) {
  final n = normalizePhMobileNumber(number);
  if (n.length < minMaskableLength) return number;
  return '${n.substring(0, 2)}${'*' * (n.length - 5)}${n.substring(n.length - 3)}';
}
