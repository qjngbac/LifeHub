import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/course/domain/course_selection.dart';

void main() {
  test('semester starts on selected Monday or the following Monday', () {
    expect(nextMondayOnOrAfter(DateTime(2026, 8, 10)), DateTime(2026, 8, 10));
    expect(nextMondayOnOrAfter(DateTime(2026, 8, 9)), DateTime(2026, 8, 10));
    expect(nextMondayOnOrAfter(DateTime(2026, 8, 11)), DateTime(2026, 8, 17));
  });

  test('odd and even selections are limited to the selected range', () {
    expect(
      weeksForRange(startWeek: 1, endWeek: 19, parity: WeekParity.odd),
      {1, 3, 5, 7, 9, 11, 13, 15, 17, 19},
    );
    expect(
      weeksForRange(startWeek: 1, endWeek: 19, parity: WeekParity.even),
      {2, 4, 6, 8, 10, 12, 14, 16, 18},
    );
    expect(
      weeksForRange(startWeek: 3, endWeek: 5, parity: WeekParity.all),
      {3, 4, 5},
    );
  });

  test('period span maps a multi-period schedule to configured rows', () {
    const periods = [
      CoursePeriod(startMinutes: 480, endMinutes: 525),
      CoursePeriod(startMinutes: 535, endMinutes: 580),
      CoursePeriod(startMinutes: 610, endMinutes: 655),
      CoursePeriod(startMinutes: 665, endMinutes: 710),
      CoursePeriod(startMinutes: 720, endMinutes: 765),
    ];

    expect(
      CoursePeriodSpan.fromMinutes(
        periods: periods,
        startMinutes: 610,
        endMinutes: 765,
      ),
      const CoursePeriodSpan(startIndex: 2, endIndex: 4),
    );
  });

  test('invalid week range and unmatched period range are rejected', () {
    expect(
      () => weeksForRange(
        startWeek: 5,
        endWeek: 3,
        parity: WeekParity.all,
      ),
      throwsArgumentError,
    );
    expect(
      () => CoursePeriodSpan.fromMinutes(
        periods: const [CoursePeriod(startMinutes: 480, endMinutes: 525)],
        startMinutes: 490,
        endMinutes: 525,
      ),
      throwsArgumentError,
    );
  });
}
