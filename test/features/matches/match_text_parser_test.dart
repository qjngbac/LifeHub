import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';

void main() {
  test('parses a date heading and two participant layouts', () {
    final result = MatchTextParser.parse(
      '''英超\n2026-09-08\n足球 20:00 阿森纳 vs 切尔西\n篮球 21：30 湖人 对 勇士''',
      referenceDate: DateTime(2026, 9, 1),
      sourceType: MatchSources.screenshot,
    );
    expect(result.drafts, hasLength(2));
    expect(result.drafts.first.matchDate, DateTime(2026, 9, 8));
    expect(result.drafts.first.startAt, DateTime.utc(2026, 9, 8, 12));
    expect(result.drafts.first.participantA, '阿森纳');
    expect(result.drafts.last.participantB, '勇士');
  });

  test('uses reference year for short dates and warns about missing time', () {
    final result = MatchTextParser.parse(
      '9/9\n网球：纳达尔 vs 德约科维奇',
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 9, 9));
    expect(result.drafts.single.startAt, isNull);
    expect(result.warnings, contains(contains('缺少开始时间')));
  });

  test('filters finished and odds rows', () {
    final result = MatchTextParser.parse(
      '英超\n赔率推荐\n完场 曼城 vs 利物浦\n足球 22:00 国米 VS 米兰',
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(result.drafts, hasLength(1));
    expect(result.drafts.single.participantA, '国米');
  });

  test('parses tennis and esports fixtures from separate competition layouts',
      () {
    final result = MatchTextParser.parse(
      '''2026-09-10
中网
网球 09:00 王欣瑜 vs 郑钦文
KPL 秋季赛
电竞 20:00 AG vs TES''',
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(result.drafts, hasLength(2));
    expect(result.drafts.first.sportType, '网球');
    expect(result.drafts.first.competition, '中网');
    expect(result.drafts.last.sportType, '电竞');
    expect(result.drafts.last.competition, 'KPL 秋季赛');
  });

  test('parses relative dates and natural Chinese times', () {
    // 2026-09-02 is Wednesday (weekday 3)
    final ref = DateTime(2026, 9, 2);
    final resultToday = MatchTextParser.parse(
      '今晚 20:00 阿森纳 vs 切尔西',
      referenceDate: ref,
    );
    expect(resultToday.drafts.single.matchDate, DateTime(2026, 9, 2));
    expect(resultToday.drafts.single.startAt, DateTime.utc(2026, 9, 2, 12));
    expect(resultToday.drafts.single.participantA, '阿森纳');
    expect(resultToday.drafts.single.participantB, '切尔西');

    final resultTomorrow = MatchTextParser.parse(
      '明天 晚上8点半 皇马 vs 曼城',
      referenceDate: ref,
    );
    expect(resultTomorrow.drafts.single.matchDate, DateTime(2026, 9, 3));
    expect(
        resultTomorrow.drafts.single.startAt, DateTime.utc(2026, 9, 3, 12, 30));

    // Wednesday -> next Saturday (diff +3 days) -> 2026-09-05
    final resultSat = MatchTextParser.parse(
      '周六 15:00 泰山 vs 申花',
      referenceDate: ref,
    );
    expect(resultSat.drafts.single.matchDate, DateTime(2026, 9, 5));
  });

  test('extracts inline competition from team prefix and brackets', () {
    final result = MatchTextParser.parse(
      '今天 20:00 英超 阿森纳 vs 切尔西\n【NBA】今晚 21:00 湖人 vs 勇士',
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(result.drafts, hasLength(2));
    expect(result.drafts.first.competition, '英超');
    expect(result.drafts.first.sportType, '足球');
    expect(result.drafts.first.participantA, '阿森纳');
    expect(result.drafts.first.participantB, '切尔西');

    expect(result.drafts.last.competition, 'NBA');
    expect(result.drafts.last.sportType, '篮球');
    expect(result.drafts.last.participantA, '湖人');
    expect(result.drafts.last.participantB, '勇士');
  });

  test('parses multi-line sports app cards without explicit vs', () {
    const text = '''
中国之队锦标赛
重庆赛
2026/09/24
19:35
中国
巴勒斯坦
-
-
中国之队锦标赛
重庆赛
2026/09/27
19:35
中国
新西兰
-
-
2026/10
中国之队锦标赛
重庆赛
2026/10/02
19:35
中国
土库曼斯坦
-
-
中国之队锦标赛
重庆赛
2026/10/06
19:35
中国
塔吉克斯坦
-
-
''';
    final result = MatchTextParser.parse(
      text,
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(result.drafts, hasLength(4));
    expect(result.drafts[0].participantA, '中国');
    expect(result.drafts[0].participantB, '巴勒斯坦');
    expect(result.drafts[0].matchDate, DateTime(2026, 9, 24));
    expect(result.drafts[0].startAt, DateTime.utc(2026, 9, 24, 11, 35));

    expect(result.drafts[1].participantA, '中国');
    expect(result.drafts[1].participantB, '新西兰');
    expect(result.drafts[1].matchDate, DateTime(2026, 9, 27));

    expect(result.drafts[2].participantA, '中国');
    expect(result.drafts[2].participantB, '土库曼斯坦');
    expect(result.drafts[2].matchDate, DateTime(2026, 10, 2));

    expect(result.drafts[3].participantA, '中国');
    expect(result.drafts[3].participantB, '塔吉克斯坦');
    expect(result.drafts[3].matchDate, DateTime(2026, 10, 6));
  });
}
