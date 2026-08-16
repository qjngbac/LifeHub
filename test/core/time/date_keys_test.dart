import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/time/date_keys.dart';

void main() {
  test('local date key round-trips without timezone conversion', () {
    final source = DateTime(2026, 8, 8, 23, 45);

    final key = DateKeys.toLocalDateKey(source);
    final restored = DateKeys.fromLocalDateKey(key);

    expect(key, 20260808);
    expect(restored, DateTime(2026, 8, 8));
  });

  test('semester week is one-based and null outside its range', () {
    final start = DateTime(2026, 9, 7);
    final end = DateTime(2027, 1, 24);

    expect(DateKeys.semesterWeek(DateTime(2026, 9, 7), start, end), 1);
    expect(DateKeys.semesterWeek(DateTime(2026, 9, 13), start, end), 1);
    expect(DateKeys.semesterWeek(DateTime(2026, 9, 14), start, end), 2);
    expect(DateKeys.semesterWeek(DateTime(2026, 9, 6), start, end), isNull);
    expect(DateKeys.semesterWeek(DateTime(2027, 1, 25), start, end), isNull);
  });

  test('week set accepts ranges and rejects invalid weeks', () {
    expect(DateKeys.parseWeekSet('1-3,5,8-9', totalWeeks: 16), {
      1,
      2,
      3,
      5,
      8,
      9,
    });
    expect(
      () => DateKeys.parseWeekSet('0,2', totalWeeks: 16),
      throwsFormatException,
    );
    expect(
      () => DateKeys.parseWeekSet('1-17', totalWeeks: 16),
      throwsFormatException,
    );
  });
}
