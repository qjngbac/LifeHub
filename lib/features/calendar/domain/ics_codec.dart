import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class CalendarExchangeItem {
  const CalendarExchangeItem({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.notes,
  });

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? notes;
}

class IcsImportResult {
  const IcsImportResult({
    required this.items,
    required this.warnings,
  });

  final List<CalendarExchangeItem> items;
  final List<String> warnings;
}

abstract final class IcsCodec {
  static String encode(List<CalendarExchangeItem> items) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//LifeHub//Android//ZH',
      'CALSCALE:GREGORIAN',
    ];
    for (final item in items) {
      if (!item.end.isAfter(item.start)) {
        throw ArgumentError('Calendar item end must be after start.');
      }
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${_escape(item.uid)}')
        ..add('SUMMARY:${_escape(item.title)}');
      if (item.allDay) {
        lines
          ..add('DTSTART;VALUE=DATE:${_date(item.start)}')
          ..add('DTEND;VALUE=DATE:${_date(item.end)}');
      } else {
        lines
          ..add('DTSTART:${_dateTime(item.start.toUtc())}')
          ..add('DTEND:${_dateTime(item.end.toUtc())}');
      }
      if (item.location != null && item.location!.trim().isNotEmpty) {
        lines.add('LOCATION:${_escape(item.location!.trim())}');
      }
      if (item.notes != null && item.notes!.trim().isNotEmpty) {
        lines.add('DESCRIPTION:${_escape(item.notes!.trim())}');
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');
    return '${lines.join('\r\n')}\r\n';
  }

  static IcsImportResult decode(String source) {
    timezone_data.initializeTimeZones();
    final raw = source.replaceAll('\r\n', '\n').split('\n');
    final lines = <String>[];
    for (final line in raw) {
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += line.substring(1);
      } else {
        lines.add(line);
      }
    }
    final items = <CalendarExchangeItem>[];
    final warnings = <String>[];
    Map<String, String>? event;
    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        event = <String, String>{};
        continue;
      }
      if (line == 'END:VEVENT') {
        if (event != null) {
          try {
            items.add(_parseEvent(event));
          } on FormatException catch (error) {
            warnings.add(error.message);
          }
        }
        event = null;
        continue;
      }
      if (event == null) continue;
      final separator = line.indexOf(':');
      if (separator < 1) continue;
      final key = line.substring(0, separator);
      final value = line.substring(separator + 1);
      event[key] = value;
      if (key.startsWith('RRULE')) {
        warnings.add('重复规则需要在导入预览中手工确认。');
      }
    }
    return IcsImportResult(
      items: List.unmodifiable(items),
      warnings: List.unmodifiable(warnings),
    );
  }

  static CalendarExchangeItem _parseEvent(Map<String, String> values) {
    final uid = _unescape(values['UID'] ?? '');
    final title = _unescape(values['SUMMARY'] ?? '');
    if (title.trim().isEmpty) throw const FormatException('日历项目缺少标题。');
    final allDayKey = values.keys
        .where((key) => key.startsWith('DTSTART;VALUE=DATE'))
        .firstOrNull;
    final allDayEndKey = values.keys
        .where((key) => key.startsWith('DTEND;VALUE=DATE'))
        .firstOrNull;
    final allDay = allDayKey != null;
    final startEntry = allDay
        ? null
        : values.entries
            .where((entry) => entry.key.startsWith('DTSTART'))
            .firstOrNull;
    final endEntry = allDay
        ? null
        : values.entries
            .where((entry) => entry.key.startsWith('DTEND'))
            .firstOrNull;
    final startText = allDay ? values[allDayKey] : startEntry?.value;
    final endText = allDay
        ? (allDayEndKey == null ? null : values[allDayEndKey])
        : endEntry?.value;
    if (startText == null || endText == null) {
      throw const FormatException('日历项目缺少开始或结束时间。');
    }
    final start = allDay
        ? _parseDate(startText)
        : _parseDateTime(startText, timezoneId: _timezoneId(startEntry!.key));
    final end = allDay
        ? _parseDate(endText)
        : _parseDateTime(endText, timezoneId: _timezoneId(endEntry!.key));
    if (!end.isAfter(start)) {
      throw const FormatException('日历项目的结束时间无效。');
    }
    return CalendarExchangeItem(
      uid: uid.isEmpty ? '$title-${start.millisecondsSinceEpoch}' : uid,
      title: title,
      start: start,
      end: end,
      allDay: allDay,
      location: _nullableUnescape(values['LOCATION']),
      notes: _nullableUnescape(values['DESCRIPTION']),
    );
  }

  static String _date(DateTime value) =>
      value.year.toString().padLeft(4, '0') +
      value.month.toString().padLeft(2, '0') +
      value.day.toString().padLeft(2, '0');

  static String _dateTime(DateTime value) =>
      '${_date(value)}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}${value.second.toString().padLeft(2, '0')}Z';

  static DateTime _parseDate(String value) {
    if (value.length != 8) throw const FormatException('无效的全天日期。');
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
    );
  }

  static DateTime _parseDateTime(String value, {String? timezoneId}) {
    final utc = value.endsWith('Z');
    final raw = utc ? value.substring(0, value.length - 1) : value;
    if (raw.length < 15) throw const FormatException('无效的日历时间。');
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(4, 6));
    final day = int.parse(raw.substring(6, 8));
    final hour = int.parse(raw.substring(9, 11));
    final minute = int.parse(raw.substring(11, 13));
    final second = int.parse(raw.substring(13, 15));
    if (utc) return DateTime.utc(year, month, day, hour, minute, second);
    if (timezoneId != null) {
      try {
        return timezone.TZDateTime(
          timezone.getLocation(timezoneId),
          year,
          month,
          day,
          hour,
          minute,
          second,
        ).toUtc();
      } on timezone.LocationNotFoundException {
        throw FormatException('日历使用了不支持的时区：$timezoneId');
      }
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  static String? _timezoneId(String propertyKey) {
    for (final parameter in propertyKey.split(';').skip(1)) {
      final separator = parameter.indexOf('=');
      if (separator > 0 &&
          parameter.substring(0, separator).toUpperCase() == 'TZID') {
        final value = parameter.substring(separator + 1).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  static String _unescape(String value) => value
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  static String? _nullableUnescape(String? value) {
    if (value == null || value.isEmpty) return null;
    return _unescape(value);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
