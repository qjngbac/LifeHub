enum SubscriptionCycleUnit { week, month, year, fixedDays }

extension SubscriptionCycleUnitValue on SubscriptionCycleUnit {
  String get dbValue => switch (this) {
        SubscriptionCycleUnit.week => 'WEEK',
        SubscriptionCycleUnit.month => 'MONTH',
        SubscriptionCycleUnit.year => 'YEAR',
        SubscriptionCycleUnit.fixedDays => 'FIXED_DAYS',
      };

  static SubscriptionCycleUnit fromDb(String value) => switch (value) {
        'WEEK' => SubscriptionCycleUnit.week,
        'MONTH' => SubscriptionCycleUnit.month,
        'YEAR' => SubscriptionCycleUnit.year,
        'FIXED_DAYS' => SubscriptionCycleUnit.fixedDays,
        _ => throw ArgumentError.value(value, 'cycleUnit'),
      };
}

abstract final class SubscriptionRules {
  static DateTime nextRenewal({
    required DateTime from,
    required SubscriptionCycleUnit unit,
    int interval = 1,
    int? fixedDays,
  }) {
    if (interval <= 0) throw RangeError('周期间隔必须大于 0');
    switch (unit) {
      case SubscriptionCycleUnit.week:
        return from.add(Duration(days: 7 * interval));
      case SubscriptionCycleUnit.fixedDays:
        if (fixedDays == null || fixedDays <= 0) {
          throw RangeError('固定天数必须大于 0');
        }
        return from.add(Duration(days: fixedDays * interval));
      case SubscriptionCycleUnit.month:
        return _calendarDate(from, months: interval);
      case SubscriptionCycleUnit.year:
        return _calendarDate(from, months: 12 * interval);
    }
  }

  static DateTime _calendarDate(DateTime from, {required int months}) {
    final monthIndex = from.month - 1 + months;
    final year = from.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return DateTime(
      year,
      month,
      day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    );
  }
}
