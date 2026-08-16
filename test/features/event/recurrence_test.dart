import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/event/domain/recurrence.dart';

void main() {
  test('daily recurrence expands only inside the visible window', () {
    final starts = Recurrence.expandStarts(
      sourceStart: DateTime.utc(2026, 8, 1, 9),
      rule: 'FREQ=DAILY;INTERVAL=1',
      windowStart: DateTime.utc(2026, 8, 3),
      windowEnd: DateTime.utc(2026, 8, 6),
    );

    expect(starts, [
      DateTime.utc(2026, 8, 3, 9),
      DateTime.utc(2026, 8, 4, 9),
      DateTime.utc(2026, 8, 5, 9),
    ]);
  });

  test('weekly recurrence preserves weekday and interval', () {
    final starts = Recurrence.expandStarts(
      sourceStart: DateTime.utc(2026, 8, 3, 14),
      rule: 'FREQ=WEEKLY;INTERVAL=2',
      windowStart: DateTime.utc(2026, 8, 1),
      windowEnd: DateTime.utc(2026, 9, 1),
    );

    expect(starts, [
      DateTime.utc(2026, 8, 3, 14),
      DateTime.utc(2026, 8, 17, 14),
      DateTime.utc(2026, 8, 31, 14),
    ]);
  });
}
