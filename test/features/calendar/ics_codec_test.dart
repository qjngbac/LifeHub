import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/calendar/domain/ics_codec.dart';

void main() {
  test('timed and all-day items round trip with escaped text', () {
    final source = [
      CalendarExchangeItem(
        uid: 'timed-1',
        title: '会议,讨论',
        start: DateTime.utc(2026, 8, 9, 7),
        end: DateTime.utc(2026, 8, 9, 8),
        notes: '第一行\n第二行',
      ),
      CalendarExchangeItem(
        uid: 'day-1',
        title: '纪念日',
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 11),
        allDay: true,
      ),
    ];

    final encoded = IcsCodec.encode(source);
    final decoded = IcsCodec.decode(encoded);

    expect(decoded.warnings, isEmpty);
    expect(decoded.items.map((item) => item.title), ['会议,讨论', '纪念日']);
    expect(decoded.items.last.allDay, isTrue);
    expect(decoded.items.first.notes, '第一行\n第二行');
  });

  test('TZID values are converted using the declared timezone', () {
    const source = 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:shanghai-1\r\n'
        'SUMMARY:Morning class\r\n'
        'DTSTART;TZID=Asia/Shanghai:20260810T090000\r\n'
        'DTEND;TZID=Asia/Shanghai:20260810T100000\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';

    final result = IcsCodec.decode(source);

    expect(result.warnings, isEmpty);
    expect(result.items.single.start, DateTime.utc(2026, 8, 10, 1));
    expect(result.items.single.end, DateTime.utc(2026, 8, 10, 2));
  });
}
