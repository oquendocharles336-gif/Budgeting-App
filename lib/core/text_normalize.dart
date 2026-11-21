/// Normalizes merchant/description text so that "JOLLIBEE - SM North!!"
/// and "jollibee sm north" compare as equal.
String normalizeText(String input) {
  final lower = input.toLowerCase();
  final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return cleaned.trim().replaceAll(RegExp(r'\s+'), ' ');
}
