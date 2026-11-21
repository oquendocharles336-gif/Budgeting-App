import '../../core/text_normalize.dart';
import '../../data/models/category.dart';

/// Picks a category from keyword rules the user can edit.
///
/// A keyword matches when a word in the description starts with it:
/// "mcdonald" matches "McDonald's Katipunan"; "grab" matches "GRABFOOD".
/// When several keywords match, the highest priority wins, then the
/// longest keyword (so "grabfood" beats "grab").
class AutoCategorizer {
  AutoCategorizer(List<CategoryRule> rules, {this.fallbackCategoryId})
      : _rules = [
          for (final r in rules)
            if (normalizeText(r.keyword).isNotEmpty)
              (keyword: normalizeText(r.keyword), rule: r),
        ];

  final List<({String keyword, CategoryRule rule})> _rules;
  final int? fallbackCategoryId;

  int? categorize(String description) => match(description)?.categoryId ?? fallbackCategoryId;

  /// The winning rule, or null when none match.
  CategoryRule? match(String description) {
    final text = ' ${normalizeText(description)}';
    CategoryRule? best;
    var bestLength = -1;
    for (final r in _rules) {
      if (!text.contains(' ${r.keyword}')) continue;
      final better = best == null ||
          r.rule.priority > best.priority ||
          (r.rule.priority == best.priority && r.keyword.length > bestLength);
      if (better) {
        best = r.rule;
        bestLength = r.keyword.length;
      }
    }
    return best;
  }
}
