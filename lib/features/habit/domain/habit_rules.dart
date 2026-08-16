abstract final class HabitRules {
  static String label(String rule) {
    if (rule == 'DAILY') return '每天';
    if (rule == 'WEEKDAYS') return '工作日';
    if (rule.startsWith('WEEKLY_X:')) {
      return '每周 ${weeklyTarget(rule)} 次';
    }
    if (rule.startsWith('WEEKDAY_SET:')) {
      final days = _weekdaySet(rule).toList()..sort();
      if (days.length == 2 && days[0] == 6 && days[1] == 7) {
        return '休息日（周六、周日）';
      }
      const names = <int, String>{
        1: '一',
        2: '二',
        3: '三',
        4: '四',
        5: '五',
        6: '六',
        7: '日',
      };
      return '每周${days.map((day) => names[day]).join('、')}';
    }
    throw FormatException('Unsupported habit schedule: $rule');
  }

  static bool isScheduled(String rule, DateTime date) {
    if (rule == 'DAILY') return true;
    if (rule == 'WEEKDAYS') return date.weekday <= DateTime.friday;
    if (rule.startsWith('WEEKLY_X:')) {
      weeklyTarget(rule);
      return true;
    }
    if (rule.startsWith('WEEKDAY_SET:')) {
      return _weekdaySet(rule).contains(date.weekday);
    }
    throw FormatException('Unsupported habit schedule: $rule');
  }

  static int weeklyTarget(String rule) {
    if (rule == 'DAILY') return 7;
    if (rule == 'WEEKDAYS') return 5;
    if (rule.startsWith('WEEKLY_X:')) {
      final value = int.tryParse(rule.substring('WEEKLY_X:'.length));
      if (value == null || value < 1 || value > 7) {
        throw FormatException('Invalid weekly habit target: $rule');
      }
      return value;
    }
    if (rule.startsWith('WEEKDAY_SET:')) return _weekdaySet(rule).length;
    throw FormatException('Unsupported habit schedule: $rule');
  }

  static Set<int> _weekdaySet(String rule) {
    final values = rule.substring('WEEKDAY_SET:'.length).split(',');
    final result = <int>{};
    for (final source in values) {
      final value = int.tryParse(source.trim());
      if (value == null || value < 1 || value > 7) {
        throw FormatException('Invalid weekday in habit schedule: $rule');
      }
      result.add(value);
    }
    if (result.isEmpty) throw const FormatException('Empty habit weekday set.');
    return result;
  }
}
