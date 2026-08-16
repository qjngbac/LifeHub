import 'package:lifehub/features/course/data/course_repository.dart';

enum WeekParity { all, odd, even }

DateTime nextMondayOnOrAfter(DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  final daysUntilMonday = (DateTime.monday - date.weekday + 7) % 7;
  return date.add(Duration(days: daysUntilMonday));
}

Set<int> weeksForRange({
  required int startWeek,
  required int endWeek,
  required WeekParity parity,
}) {
  if (startWeek < 1 || endWeek < startWeek) {
    throw ArgumentError('上课周次范围无效');
  }

  return {
    for (var week = startWeek; week <= endWeek; week++)
      if (parity == WeekParity.all ||
          (parity == WeekParity.odd && week.isOdd) ||
          (parity == WeekParity.even && week.isEven))
        week,
  };
}

String formatWeekSet(Set<int> weeks) {
  if (weeks.isEmpty) {
    throw ArgumentError('至少选择一周');
  }
  final sorted = weeks.toList()..sort();
  return sorted.join(',');
}

class CoursePeriodSpan {
  const CoursePeriodSpan({required this.startIndex, required this.endIndex});

  factory CoursePeriodSpan.fromMinutes({
    required List<CoursePeriod> periods,
    required int startMinutes,
    required int endMinutes,
  }) {
    final startIndex = periods.indexWhere(
      (period) => period.startMinutes == startMinutes,
    );
    final endIndex = periods.indexWhere(
      (period) => period.endMinutes == endMinutes,
    );
    if (startIndex < 0 || endIndex < startIndex) {
      throw ArgumentError('课程时间必须与已设置的节次边界一致');
    }
    return CoursePeriodSpan(startIndex: startIndex, endIndex: endIndex);
  }

  final int startIndex;
  final int endIndex;

  int get length => endIndex - startIndex + 1;

  @override
  bool operator ==(Object other) =>
      other is CoursePeriodSpan &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex;

  @override
  int get hashCode => Object.hash(startIndex, endIndex);
}
