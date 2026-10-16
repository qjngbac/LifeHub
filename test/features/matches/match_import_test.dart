import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/matches/application/match_file_codecs.dart';
import 'package:lifehub/features/matches/application/match_import_service.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';

void main() {
  test('CSV template round trips through the codec', () {
    final preview = MatchImportService().previewCsv(
      MatchFileCodecs.encodeCsvTemplate(),
      referenceDate: DateTime(2026, 9, 1),
    );
    expect(preview.rows, hasLength(1));
    expect(preview.rows.single.draft.participantA, '阿森纳');
    expect(preview.rows.single.draft.matchDate, DateTime(2026, 9, 7));
  });

  test('CSV missing core fields enters invalid preview state', () {
    final preview = MatchImportService().previewCsv(
      '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间\n足球,英超,,,2026-09-07,20:00',
    );
    expect(preview.rows.single.state, MatchPreviewState.invalid);
    expect(preview.rows.single.issues, isNotEmpty);
  });

  test('CSV resolves wall clock time in its declared timezone', () {
    const source =
        '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n足球,美职联,纽约,迈阿密,2026-09-07,20:00,America/New_York';

    final row = MatchImportService().previewCsv(source).rows.single;

    expect(row.draft.startAt, DateTime.utc(2026, 9, 8));
    expect(row.draft.matchDate, DateTime(2026, 9, 7));
    expect(row.draft.timezoneId, 'America/New_York');
  });

  test('invalid CSV timezone is an import validation issue', () {
    const source =
        '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n足球,英超,阿森纳,切尔西,2026-09-07,20:00,Mars/Olympus';

    final row = MatchImportService().previewCsv(source).rows.single;

    expect(row.state, MatchPreviewState.invalid);
    expect(
      row.issues,
      contains(predicate<MatchImportIssue>(
        (issue) => issue.code == 'INVALID_TIMEZONE',
      )),
    );
  });

  test('OCR import enforces image count before invoking service', () async {
    final files = List<File>.generate(21, (index) => File('image-$index.jpg'));
    await expectLater(
      MatchImportService().previewOcr(
        files,
        referenceDate: DateTime(2026, 9, 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('ICS keeps event start time in the preview', () {
    const source = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:match-1
DTSTART:20990907T120000Z
DTEND:20990907T140000Z
SUMMARY:阿森纳 vs 切尔西
LOCATION:主体育场
END:VEVENT
END:VCALENDAR''';
    final row = MatchImportService().previewIcs(source).rows.single;
    expect(row.draft.startAt, isNotNull);
    expect(row.draft.participantA, '阿森纳');
    expect(row.state, MatchPreviewState.ready);
  });

  test('ICS preserves its declared timezone and source-local date', () {
    const source = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:ny-match
DTSTART;TZID=America/New_York:20260907T200000
DTEND;TZID=America/New_York:20260907T220000
SUMMARY:纽约 vs 迈阿密
END:VEVENT
END:VCALENDAR''';

    final row = MatchImportService().previewIcs(source).rows.single;

    expect(row.draft.startAt, DateTime.utc(2026, 9, 8));
    expect(row.draft.matchDate, DateTime(2026, 9, 7));
    expect(row.draft.timezoneId, 'America/New_York');
  });

  test('invalid ICS timezone is exposed as an import warning', () {
    const source = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:invalid-zone
DTSTART;TZID=Mars/Olympus:20260907T200000
DTEND;TZID=Mars/Olympus:20260907T220000
SUMMARY:火星队 vs 地球队
END:VEVENT
END:VCALENDAR''';

    final preview = MatchImportService().previewIcs(source);

    expect(preview.rows, isEmpty);
    expect(preview.warnings, contains(contains('Mars/Olympus')));
  });

  test('duplicate import defaults to skip and selected row updates existing',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final service = MatchImportService();
    const source =
        '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n足球,英超,阿森纳,切尔西,2099-09-07,20:00,Asia/Shanghai';
    final draft = service.previewCsv(source).rows.single.draft;
    final existing = await repository.create(draft);

    final preview = await service.previewCsvWithRepository(source, repository);
    expect(preview.rows.single.possibleDuplicate, isTrue);
    expect(preview.rows.single.selected, isFalse);
    expect(preview.rows.single.existingId, existing.id);

    final selected = MatchImportPreview(
      rows: [preview.rows.single.copyWith(selected: true)],
      warnings: preview.warnings,
    );
    await service.saveSelectedWithRepository(selected, repository);
    expect(await database.select(database.matchRecords).get(), hasLength(1));
  });

  test('CSV row positions are not treated as stable duplicate source keys',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final service = MatchImportService();
    const first =
        '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n足球,英超,阿森纳,切尔西,2099-09-07,20:00,Asia/Shanghai';
    const differentMatch =
        '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n足球,英超,利物浦,曼城,2099-09-07,20:00,Asia/Shanghai';
    await repository.create(service.previewCsv(first).rows.single.draft);

    final preview =
        await service.previewCsvWithRepository(differentMatch, repository);
    expect(preview.rows.single.possibleDuplicate, isFalse);
    expect(preview.rows.single.selected, isTrue);
  });

  test('later normalized duplicate in one CSV preview is not inserted',
      () async {
    const source = '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区\n'
        '足球,英超,阿森纳,切尔西,2099-09-07,20:00,Asia/Shanghai\n'
        '足球,英超,阿森纳,切尔西,2099-09-07,20:00,Asia/Shanghai';

    final preview = MatchImportService().previewCsv(source);

    expect(preview.rows, hasLength(2));
    expect(preview.rows.first.state, MatchPreviewState.ready);
    expect(preview.rows.first.selected, isTrue);
    expect(preview.rows.last.state, MatchPreviewState.duplicate);
    expect(preview.rows.last.possibleDuplicate, isTrue);
    expect(preview.rows.last.selected, isFalse);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MatchImportService().saveSelectedWithRepository(
      preview,
      MatchRepository(database),
    );
    expect(await database.select(database.matchRecords).get(), hasLength(1));
  });

  test('later stable source duplicate in one ICS preview defaults to skipped',
      () {
    const source = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:same-source
DTSTART:20990907T120000Z
DTEND:20990907T140000Z
SUMMARY:阿森纳 vs 切尔西
END:VEVENT
BEGIN:VEVENT
UID:same-source
DTSTART:20990908T120000Z
DTEND:20990908T140000Z
SUMMARY:利物浦 vs 曼城
END:VEVENT
END:VCALENDAR''';

    final preview = MatchImportService().previewIcs(source);

    expect(preview.rows, hasLength(2));
    expect(preview.rows.first.state, MatchPreviewState.ready);
    expect(preview.rows.last.state, MatchPreviewState.duplicate);
    expect(preview.rows.last.possibleDuplicate, isTrue);
    expect(preview.rows.last.selected, isFalse);
  });

  test('encodeCsv and encodeIcs output valid formats', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final entry = await repository.create(MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2026, 9, 7),
      startAt: DateTime.utc(2026, 9, 7, 12),
      timezoneId: 'Asia/Shanghai',
      status: MatchStatuses.scheduled,
    ));

    final csvText = MatchFileCodecs.encodeCsv([entry]);
    expect(csvText, contains('阿森纳'));
    expect(csvText, contains('切尔西'));
    expect(csvText, contains('2026-09-07'));

    final icsText = MatchFileCodecs.encodeIcs([entry]);
    expect(icsText, contains('BEGIN:VCALENDAR'));
    expect(icsText, contains('阿森纳 vs 切尔西'));
    expect(icsText, contains('END:VCALENDAR'));
  });
}
