import 'package:budgeting_app/data/db/default_data.dart';
import 'package:budgeting_app/data/models/category.dart';
import 'package:budgeting_app/domain/import/auto_categorizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = AutoCategorizer(DefaultData.rules, fallbackCategoryId: DefaultData.other);

  test('matches keywords at the start of a word, any case', () {
    expect(c.categorize("McDonald's Katipunan"), DefaultData.food);
    expect(c.categorize('MERALCO BILLS PAYMENT'), DefaultData.utilities);
    expect(c.categorize('Mercury Drug - QC'), DefaultData.health);
  });

  test('utility keywords: "globe at home" (WiFi) beats "globe" (Utilities)', () {
    final rules = [
      for (final (i, e) in DefaultData.utilityKeywords.entries.indexed)
        for (final kw in e.value) CategoryRule(keyword: kw, categoryId: 100 + i),
    ];
    final u = AutoCategorizer(rules);
    final id = {for (final (i, k) in DefaultData.utilityKeywords.keys.indexed) k: 100 + i};
    expect(u.categorize('MAYNILAD WATER SERVICES'), id['Water']);
    expect(u.categorize('Meralco bill'), id['Electricity']);
    expect(u.categorize('GLOBE AT HOME PREPAID WIFI'), id['WiFi']);
    expect(u.categorize('Globe load'), id['Utilities']);
  });

  test('longest keyword wins: grabfood beats grab', () {
    expect(c.categorize('GRABFOOD MAKATI'), DefaultData.food);
    expect(c.categorize('GRAB* RIDE 1234'), DefaultData.transport);
  });

  test('does not match in the middle of a word', () {
    // "rent" must not match "current".
    expect(c.categorize('current account fee'), DefaultData.other);
  });

  test('falls back when nothing matches', () {
    expect(c.categorize('Tita Lorna'), DefaultData.other);
    expect(AutoCategorizer(const []).categorize('anything'), isNull);
  });

  test('priority beats length', () {
    final custom = AutoCategorizer(const [
      CategoryRule(keyword: 'grab', categoryId: 2, priority: 5),
      CategoryRule(keyword: 'grabfood', categoryId: 1),
    ]);
    expect(custom.categorize('GRABFOOD'), 2);
  });
}
