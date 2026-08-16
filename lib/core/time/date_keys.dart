abstract final class DateKeys {
  static int toLocalDateKey(DateTime value) {
    return value.year * 10000 + value.month * 100 + value.day;
  }

  static DateTime fromLocalDateKey(int key) {
    final year = key ~/ 10000;
    final month = (key ~/ 100) % 100;
    final day = key % 100;
    final value = DateTime(year, month, day);
    if (toLocalDateKey(value) != key) {
      throw FormatException('Invalid local date key: $key');
    }
    return value;
  }

  static int? semesterWeek(
    DateTime date,
    DateTime semesterStart,
    DateTime semesterEnd,
  ) {
    final target = DateTime(date.year, date.month, date.day);
    final start = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    final end = DateTime(
      semesterEnd.year,
      semesterEnd.month,
      semesterEnd.day,
    );
    if (end.isBefore(start)) {
      throw ArgumentError('Semester end must not be before its start.');
    }
    if (target.isBefore(start) || target.isAfter(end)) {
      return null;
    }
    return target.difference(start).inDays ~/ 7 + 1;
  }

  static Set<int> parseWeekSet(String source, {required int totalWeeks}) {
    if (totalWeeks < 1) {
      throw ArgumentError.value(totalWeeks, 'totalWeeks');
    }
    if (source.trim().isEmpty) {
      throw const FormatException('Week set cannot be empty.');
    }

    final result = <int>{};
    for (final rawPart in source.split(',')) {
      final part = rawPart.trim();
      final bounds = part.split('-');
      if (bounds.length == 1) {
        result.add(_parseWeek(bounds.single, totalWeeks));
        continue;
      }
      if (bounds.length != 2) {
        throw FormatException('Invalid week segment: $part');
      }
      final start = _parseWeek(bounds.first, totalWeeks);
      final end = _parseWeek(bounds.last, totalWeeks);
      if (start > end) {
        throw FormatException('Invalid descending week range: $part');
      }
      result.addAll(Iterable<int>.generate(end - start + 1, (i) => start + i));
    }
    return result;
  }

  static int _parseWeek(String source, int totalWeeks) {
    final week = int.tryParse(source.trim());
    if (week == null || week < 1 || week > totalWeeks) {
      throw FormatException('Invalid week: $source');
    }
    return week;
  }
}
