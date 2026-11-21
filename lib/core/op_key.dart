import 'dart:math';

final _random = Random.secure();

/// A new key for one user action ("save this order"). Keep it for retries
/// so the same action is never written twice.
String newOpKey(String action) {
  final r = List.generate(4, (_) => _random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')).join();
  return '$action:${DateTime.now().microsecondsSinceEpoch}:$r';
}
