import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';

void main() {
  test('schedule rules cover daily weekdays weekly count and weekday set', () {
    final monday = DateTime(2026, 8, 3);
    final saturday = DateTime(2026, 8, 8);

    expect(HabitRules.isScheduled('DAILY', saturday), isTrue);
    expect(HabitRules.isScheduled('WEEKDAYS', monday), isTrue);
    expect(HabitRules.isScheduled('WEEKDAYS', saturday), isFalse);
    expect(HabitRules.isScheduled('WEEKLY_X:3', saturday), isTrue);
    expect(HabitRules.weeklyTarget('WEEKLY_X:3'), 3);
    expect(HabitRules.isScheduled('WEEKDAY_SET:1,3,5', monday), isTrue);
    expect(HabitRules.isScheduled('WEEKDAY_SET:2,4', monday), isFalse);
  });

  test('stored schedule rules are rendered as human Chinese labels', () {
    expect(HabitRules.label('DAILY'), '每天');
    expect(HabitRules.label('WEEKDAYS'), '工作日');
    expect(HabitRules.label('WEEKLY_X:3'), '每周 3 次');
    expect(HabitRules.label('WEEKDAY_SET:6,7'), '休息日（周六、周日）');
    expect(HabitRules.label('WEEKDAY_SET:2,4,6'), '每周二、四、六');
  });
}
