import 'package:budgeting_app/domain/analytics/insights_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 21, 10);

  group('earliest-date limit', () {
    final range = InsightsRange.from(DateTime(2026, 8, 14, 9), now);

    test('starts at the month of the first data and ends at this month', () {
      expect(range.earliest, DateTime(2026, 8));
      expect(range.latest, DateTime(2026, 11));
    });

    test('previous is disabled at the earliest month only', () {
      expect(range.canGoBack(DateTime(2026, 8)), isFalse);
      expect(range.canGoBack(DateTime(2026, 8, 31)), isFalse);
      expect(range.canGoBack(DateTime(2026, 9)), isTrue);
    });

    test('next is disabled at the current month', () {
      expect(range.canGoForward(DateTime(2026, 11)), isFalse);
      expect(range.canGoForward(DateTime(2026, 10)), isTrue);
    });

    test('months outside the range are pulled back in (swipe, picker, Budget)', () {
      expect(range.clamp(DateTime(2025, 1)), DateTime(2026, 8));
      expect(range.clamp(DateTime(2027, 3)), DateTime(2026, 11));
      expect(range.clamp(DateTime(2026, 9, 20)), DateTime(2026, 9));
      expect(range.contains(DateTime(2026, 7, 31)), isFalse);
      expect(range.contains(DateTime(2026, 8, 1)), isTrue);
    });

    test('date picker bounds', () {
      expect(range.firstPickable, DateTime(2026, 8));
      expect(range.lastPickable(now), DateTime(2026, 11, 21));
    });

    test('crosses a year boundary', () {
      final r = InsightsRange.from(DateTime(2025, 12, 31), DateTime(2026, 1, 5));
      expect(r.canGoBack(DateTime(2026, 1)), isTrue);
      expect(r.canGoBack(DateTime(2025, 12)), isFalse);
    });
  });

  test('no data at all: only the current month, previous disabled', () {
    final r = InsightsRange.from(null, now);
    expect(r.earliest, DateTime(2026, 11));
    expect(r.canGoBack(DateTime(2026, 11)), isFalse);
  });

  test('a future-dated first expense does not push the start past today', () {
    final r = InsightsRange.from(DateTime(2027, 2, 1), now);
    expect(r.earliest, DateTime(2026, 11));
    expect(r.canGoBack(DateTime(2026, 11)), isFalse);
  });
}
