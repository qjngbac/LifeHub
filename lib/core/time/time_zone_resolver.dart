import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

abstract final class TimeZoneResolver {
  static bool _initialized = false;

  static timezone.Location requireLocation(String timezoneId) {
    _ensureInitialized();
    final id = timezoneId.trim();
    if (id.isEmpty) throw const FormatException('时区不能为空。');
    if (id.toUpperCase() == 'UTC') return timezone.UTC;
    try {
      return timezone.getLocation(id);
    } on timezone.LocationNotFoundException {
      throw FormatException('不支持的时区：$id');
    }
  }

  static bool isValid(String timezoneId) {
    try {
      requireLocation(timezoneId);
      return true;
    } on FormatException {
      return false;
    }
  }

  static DateTime resolveLocal(DateTime wallClock, String timezoneId) {
    final value = timezone.TZDateTime(
      requireLocation(timezoneId),
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
      wallClock.millisecond,
      wallClock.microsecond,
    );
    if (value.year != wallClock.year ||
        value.month != wallClock.month ||
        value.day != wallClock.day ||
        value.hour != wallClock.hour ||
        value.minute != wallClock.minute ||
        value.second != wallClock.second) {
      throw FormatException('$timezoneId 中不存在该本地时间。');
    }
    return value.toUtc();
  }

  static timezone.TZDateTime atInstant(
    DateTime instant,
    String timezoneId,
  ) {
    return timezone.TZDateTime.from(
      instant.toUtc(),
      requireLocation(timezoneId),
    );
  }

  static void _ensureInitialized() {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    _initialized = true;
  }
}
