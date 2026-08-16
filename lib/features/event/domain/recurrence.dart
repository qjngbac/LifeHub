abstract final class Recurrence {
  static List<DateTime> expandStarts({
    required DateTime sourceStart,
    required String? rule,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    if (!windowEnd.isAfter(windowStart)) {
      throw ArgumentError('Window end must be after its start.');
    }
    if (rule == null || rule.trim().isEmpty) {
      return sourceStart.isBefore(windowEnd) &&
              !sourceStart.isBefore(windowStart)
          ? [sourceStart]
          : const [];
    }

    final fields = <String, String>{};
    for (final segment in rule.split(';')) {
      final parts = segment.split('=');
      if (parts.length != 2) {
        throw FormatException('Invalid recurrence segment: $segment');
      }
      fields[parts.first.toUpperCase()] = parts.last.toUpperCase();
    }
    final interval = int.tryParse(fields['INTERVAL'] ?? '1');
    if (interval == null || interval < 1) {
      throw const FormatException('Invalid recurrence interval.');
    }
    final step = switch (fields['FREQ']) {
      'DAILY' => Duration(days: interval),
      'WEEKLY' => Duration(days: 7 * interval),
      _ => throw const FormatException('Unsupported recurrence frequency.'),
    };

    var occurrence = sourceStart;
    if (occurrence.isBefore(windowStart)) {
      final elapsed = windowStart.difference(occurrence).inSeconds;
      final steps = elapsed ~/ step.inSeconds;
      occurrence = occurrence.add(step * steps);
      while (occurrence.isBefore(windowStart)) {
        occurrence = occurrence.add(step);
      }
    }

    final result = <DateTime>[];
    while (occurrence.isBefore(windowEnd)) {
      result.add(occurrence);
      occurrence = occurrence.add(step);
      if (result.length > 10000) {
        throw StateError('Recurrence expansion exceeded safe limit.');
      }
    }
    return result;
  }
}
