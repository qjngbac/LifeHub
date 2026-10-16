import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';

void main() {
  final reference = DateTime(2026, 10, 11);
  test('the clipboard example retains broadcast and participant names', () {
    final result = MatchTextParser.parse(
      '周日 20:00 英超第4轮 阿森纳 vs 切尔西 CCTV5直播',
      referenceDate: reference,
    );
    expect(result.drafts, hasLength(1));
    expect(result.drafts.single.participantA, '阿森纳');
    expect(result.drafts.single.participantB, '切尔西');
    expect(result.drafts.single.broadcast, 'CCTV5');
  });
  test(
    'mixed layouts under one date retain every fixture and long English names',
    () {
      final result = MatchTextParser.parse('''英超
2026-10-12
20:00 阿森纳 vs 切尔西
21:00
Manchester United
Liverpool''', referenceDate: reference);
      expect(result.drafts, hasLength(2));
      final second = result.drafts.singleWhere(
        (draft) => draft.participantA == 'Manchester United',
      );
      expect(second.participantB, 'Liverpool');
      expect(second.startAt, DateTime.utc(2026, 10, 12, 13));
    },
  );
  test(
    'incomplete multiline rows never take a team from the following date',
    () {
      final result = MatchTextParser.parse('''英超
2026-10-12
20:00
Only Team
2026-10-13
21:00
A United
B Club''', referenceDate: reference);
      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.matchDate, DateTime(2026, 10, 13));
      expect(result.drafts.single.participantA, 'A United');
      expect(result.drafts.single.participantB, 'B Club');
    },
  );
  test('this week stays in the current calendar week', () {
    final result = MatchTextParser.parse(
      '本周一 20:00 A队 vs B队',
      referenceDate: reference,
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 5));
  });
  test('incomplete rows never take a team from the next time heading', () {
    final result = MatchTextParser.parse('''英超
2026-10-12
19:00 C vs D
20:00
Only Team
21:00
Next A
Next B''', referenceDate: reference);
    expect(result.drafts, hasLength(2));
    final next = result.drafts.singleWhere(
      (draft) => draft.participantA == 'Next A',
    );
    expect(next.participantB, 'Next B');
    expect(next.startAt, DateTime.utc(2026, 10, 12, 13));
  });
  test('multiline broadcast headings retain opponents and provenance', () {
    final result = MatchTextParser.parse(
      '英超\n2026-10-12\n20:00 CCTV5直播\n阿森纳\n切尔西',
      referenceDate: reference,
    );
    expect(result.drafts, hasLength(1));
    expect(result.drafts.single.participantA, '阿森纳');
    expect(result.drafts.single.participantB, '切尔西');
    expect(result.drafts.single.broadcast, 'CCTV5');
    expect(
      result.drafts.single.importFields,
      contains(MatchImportField.broadcast),
    );
  });
  test('opponent columns may contain sport names and weekday-like names', () {
    final result = MatchTextParser.parse(
      '中超\n2026-10-12\n20:00\n广州足球俱乐部\t上海申花足球俱乐部',
      referenceDate: reference,
    );
    expect(result.drafts.single.participantA, '广州足球俱乐部');
    expect(result.drafts.single.participantB, '上海申花足球俱乐部');
    final badminton = MatchTextParser.parse(
      'BWF\n2026-10-12\n20:00\n周天成\t安赛龙',
      referenceDate: reference,
    );
    expect(badminton.drafts.single.participantA, '周天成');
    expect(badminton.drafts.single.matchDate, DateTime(2026, 10, 12));
    expect(badminton.drafts.single.startAt, DateTime.utc(2026, 10, 12, 12));
  });
  test('relative date prefixes still work without separating whitespace', () {
    final result = MatchTextParser.parse(
      '明天阿森纳 vs 切尔西',
      referenceDate: reference,
    );
    expect(result.drafts.single.participantA, '阿森纳');
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 12));
  });
  test('weekdays may directly precede a Chinese time period', () {
    final result = MatchTextParser.parse(
      '周一晚上8点 英超 阿森纳 vs 切尔西',
      referenceDate: reference,
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 12));
    expect(result.drafts.single.startAt, DateTime.utc(2026, 10, 12, 12));
  });
  test(
    'date on a VS fixture establishes context for the next multiline fixture',
    () {
      final result = MatchTextParser.parse(
        '英超\n2026-10-12 20:00 A vs B\n21:00\nC\nD',
        referenceDate: reference,
      );
      expect(result.drafts, hasLength(2));
      expect(
        result.drafts.every(
          (draft) => draft.competition == '英超' && draft.sportType == '足球',
        ),
        isTrue,
      );
    },
  );
  test('unknown sport is not silently labelled football', () {
    final result = MatchTextParser.parse(
      '邀请赛\n2026-10-12\n20:00\nAlpha Team\nBeta Team',
      referenceDate: reference,
    );
    expect(result.drafts.single.sportType, '其他');
    expect(result.warnings, contains(contains('运动类型')));
  });
  test('OCR columns retain the shared date and time', () {
    final result = MatchTextParser.parse(
      'NBA\n2026-10-12\n19:30\nLos Angeles Lakers\tGolden State Warriors',
      referenceDate: reference,
    );
    expect(result.drafts.single.participantA, 'Los Angeles Lakers');
    expect(result.drafts.single.participantB, 'Golden State Warriors');
    expect(result.drafts.single.startAt, DateTime.utc(2026, 10, 12, 11, 30));
  });
  test(
    'a missing year remains explicit for review instead of guessing rollover',
    () {
      final result = MatchTextParser.parse(
        '1/1 20:00 A队 vs B队',
        referenceDate: DateTime(2026, 12, 30),
      );
      expect(result.drafts.single.matchDate, DateTime(2026, 1, 1));
      expect(result.warnings, contains(contains('年份')));
    },
  );
}
