import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/matches/application/match_import_service.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_text_parser.dart';
import 'package:lifehub/features/matches/presentation/match_import_preview_page.dart';

void main() {
  for (final scenario in [
    (
      name: 'CSV identity change',
      format: 'CSV',
      editIdentity: true,
      createsNew: true
    ),
    (
      name: 'CSV unchanged identity',
      format: 'CSV',
      editIdentity: false,
      createsNew: false
    ),
    (
      name: 'ICS same UID identity change',
      format: 'ICS',
      editIdentity: true,
      createsNew: false
    ),
  ]) {
    testWidgets('match audit preview edit provenance ${scenario.name}',
        (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = MatchRepository(database);
      final existing = await repository.create(_draft().copyWith(
        sourceType: MatchSources.ics,
        sourceKey: 'existing-uid',
      ));
      final service = MatchImportService();
      final preview = scenario.format == 'CSV'
          ? await service.previewCsvWithRepository(_csv(), repository)
          : await service.previewIcsWithRepository(
              _ics('existing-uid'), repository);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(home: MatchImportPreviewPage(preview: preview)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      if (scenario.editIdentity) {
        await tester.enterText(
            find.widgetWithText(TextField, '参赛方 B *'),
            '曼城');
      }
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      if (scenario.createsNew) {
        expect(find.text('保存 1 条'), findsOneWidget);
        expect(find.text('可能已存在'), findsNothing);
      } else {
        expect(find.text('保存 0 条'), findsOneWidget);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('保存 1 条'));
      await tester.pumpAndSettle();
      final rows = await database.select(database.matchRecords).get();
      expect(rows, hasLength(scenario.createsNew ? 2 : 1));
      final original = (await repository.get(existing.id))!;
      expect(original.sourceKey, 'existing-uid');
      expect(original.participantB,
          scenario.editIdentity && !scenario.createsNew ? '曼城' : '切尔西');
      if (scenario.createsNew) {
        final added = rows.singleWhere((row) => row.id != existing.id);
        expect(added.participantB, '曼城');
        expect(added.sourceKey, isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final text in [
    '英超\n2099-09-07\n20:00 阿森纳 vs 切尔西',
    '英超\n2099-09-07\n20:00\n阿森纳\n切尔西',
  ]) {
    final layout = text.contains('vs') ? 'single line' : 'multiple lines';
    test('match audit OCR imported $layout preserves absent result fields',
        () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = MatchRepository(database);
      final existing = await repository.create(_draft().copyWith(
        status: MatchStatuses.finished,
        scoreA: 2,
        scoreB: 1,
        scoreDetail: '原结果',
        favorite: true,
        notes: '原备注',
      ));
      final parsed = MatchTextParser.parse(
        text,
        referenceDate: DateTime(2099, 9, 1),
        sourceType: MatchSources.screenshot,
      );
      final service = MatchImportService();
      final preview = await service.previewDraftsWithRepository(
        parsed.drafts,
        parsed.warnings,
        repository,
      );
      expect(preview.rows.single.existingId, existing.id);
      await service.saveSelectedWithRepository(
        MatchImportPreview(
            rows: [preview.rows.single.copyWith(selected: true)],
            warnings: preview.warnings),
        repository,
      );
      final updated = (await repository.get(existing.id))!;
      expect(updated.status, MatchStatuses.finished);
      expect(updated.scoreA, 2);
      expect(updated.scoreB, 1);
      expect(updated.scoreDetail, '原结果');
      expect(updated.favorite, isTrue);
      expect(updated.notes, '原备注');
    });
  }

  test('match audit OCR imported explicit edits still update optional fields',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      status: MatchStatuses.finished,
      scoreA: 2,
      scoreB: 1,
      scoreDetail: '原结果',
      favorite: true,
      notes: '原备注',
    ));
    final parsed = MatchTextParser.parse(
      '英超\n2099-09-07\n20:00 阿森纳 vs 切尔西',
      referenceDate: DateTime(2099, 9, 1),
      sourceType: MatchSources.screenshot,
    );
    final draft = parsed.drafts.single.copyWith(
      status: MatchStatuses.scheduled,
      stageOrRound: '第4轮',
      notes: '',
      favorite: false,
    );
    final service = MatchImportService();
    final preview = await service.previewDraftsWithRepository(
      [draft],
      parsed.warnings,
      repository,
    );
    expect(preview.rows.single.existingId, existing.id);
    await service.saveSelectedWithRepository(
      MatchImportPreview(
          rows: [preview.rows.single.copyWith(selected: true)],
          warnings: preview.warnings),
      repository,
    );
    final updated = (await repository.get(existing.id))!;
    expect(updated.status, MatchStatuses.scheduled);
    expect(updated.stageOrRound, '第4轮');
    expect(updated.notes, isNull);
    expect(updated.favorite, isFalse);
    expect(updated.scoreA, 2);
    expect(updated.scoreB, 1);
    expect(updated.scoreDetail, '原结果');
  });

  test('match audit OCR imported explicit canceled marker updates status',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      status: MatchStatuses.finished,
      scoreA: 2,
      scoreB: 1,
      scoreDetail: '原结果',
      favorite: true,
    ));
    final parsed = MatchTextParser.parse(
      '英超\n2099-09-07\n20:00 阿森纳 vs 切尔西 取消',
      referenceDate: DateTime(2099, 9, 1),
      sourceType: MatchSources.screenshot,
    );
    final service = MatchImportService();
    final preview = await service.previewDraftsWithRepository(
      parsed.drafts,
      parsed.warnings,
      repository,
    );
    expect(preview.rows.single.existingId, existing.id);
    await service.saveSelectedWithRepository(
      MatchImportPreview(
          rows: [preview.rows.single.copyWith(selected: true)],
          warnings: preview.warnings),
      repository,
    );
    final updated = (await repository.get(existing.id))!;
    expect(updated.status, MatchStatuses.cancelled);
    expect(updated.scoreA, 2);
    expect(updated.scoreB, 1);
    expect(updated.favorite, isTrue);
  });

  test('match audit explicit date takes precedence over weekday', () {
    final result = MatchTextParser.parse(
      '英超\n2026-10-12 周一\n20:00 阿森纳 vs 切尔西',
      referenceDate: DateTime(2026, 10, 4),
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 12));
    expect(result.drafts.single.startAt, DateTime.utc(2026, 10, 12, 12));
    expect(result.warnings, isEmpty);
  });

  test('match audit explicit date reports a conflicting weekday', () {
    final result = MatchTextParser.parse(
      '2026-10-12 周二\n20:00 阿森纳 vs 切尔西',
      referenceDate: DateTime(2026, 10, 4),
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 12));
    expect(result.warnings, contains(contains('星期不一致')));
  });

  test('match audit longest relative date is three days later', () {
    final result = MatchTextParser.parse(
      '大后天 20:00 阿森纳 vs 切尔西',
      referenceDate: DateTime(2026, 10, 4),
    );
    expect(result.drafts.single.matchDate, DateTime(2026, 10, 7));
  });

  test('match audit invalid explicit date never falls back to weekday', () {
    final result = MatchTextParser.parse(
      '2026-02-30 周一\n20:00 阿森纳 vs 切尔西',
      referenceDate: DateTime(2026, 10, 4),
    );
    expect(result.drafts.single.matchDate, isNull);
    expect(result.warnings, contains(contains('日期无效')));
  });

  for (final zone in ['Asia/Shanghai', 'America/New_York']) {
    testWidgets('match audit preview uses the declared timezone $zone',
        (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final preview = MatchImportService().previewCsv(_csv(timezone: zone));
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(home: MatchImportPreviewPage(preview: preview)),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('2099-09-07 20:00 ($zone)'), findsOneWidget);
    });
  }

  test('match audit manual record is detected when importing ICS', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft());
    final service = MatchImportService();
    final preview =
        await service.previewIcsWithRepository(_ics('new-uid'), repository);
    expect(preview.rows.single.existingId, existing.id);
    expect(preview.rows.single.selected, isFalse);
    await service.saveSelectedWithRepository(preview, repository);
    expect(await database.select(database.matchRecords).get(), hasLength(1));
  });

  test('match audit ICS record is detected for CSV and another ICS UID',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      sourceType: MatchSources.ics,
      sourceKey: 'first-uid',
    ));
    final service = MatchImportService();
    final csv = await service.previewCsvWithRepository(_csv(), repository);
    final ics =
        await service.previewIcsWithRepository(_ics('second-uid'), repository);
    for (final preview in [csv, ics]) {
      expect(preview.rows.single.existingId, existing.id);
      expect(preview.rows.single.selected, isFalse);
    }
  });

  test('match audit identity keeps distinct rounds and start times', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final first = _draft().copyWith(stageOrRound: '第1轮');
    await repository.create(first);
    final second = first.copyWith(stageOrRound: '第2轮');
    expect(await repository.findPossibleDuplicates(second), isEmpty);
    expect(
        await repository.findPossibleDuplicates(first.copyWith(
          startAt: DateTime.utc(2099, 9, 7, 13),
        )),
        isEmpty);
    final preview = await MatchImportService().previewDraftsWithRepository(
      [first, second],
      const [],
      repository,
    );
    expect(preview.rows.first.state, MatchPreviewState.duplicate);
    expect(preview.rows.last.state, MatchPreviewState.ready);
    await repository.importBatch([(draft: second, existingId: null)]);
    expect(await database.select(database.matchRecords).get(), hasLength(2));
  });

  test('match audit same instant matches across timezone date boundaries',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      matchDate: DateTime(2099, 9, 8),
      startAt: DateTime.utc(2099, 9, 8),
    ));
    final duplicates =
        await repository.findPossibleDuplicates(_draft().copyWith(
      matchDate: DateTime(2099, 9, 7),
      startAt: DateTime.utc(2099, 9, 8),
      timezoneId: 'America/New_York',
      sourceKey: 'ny-uid',
    ));
    expect(duplicates.map((row) => row.id), [existing.id]);
  });

  for (final format in ['CSV', 'ICS']) {
    test(
        'match audit $format update preserves absent result and favorite fields',
        () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = MatchRepository(database);
      final existing = await repository.create(_draft().copyWith(
        status: MatchStatuses.finished,
        scoreA: 2,
        scoreB: 1,
        scoreDetail: '点球后结束',
        favorite: true,
        sourceKey: format == 'ICS' ? 'existing-uid' : null,
      ));
      final service = MatchImportService();
      final preview = format == 'CSV'
          ? await service.previewCsvWithRepository(_csv(), repository)
          : await service.previewIcsWithRepository(
              _ics('existing-uid'), repository);
      expect(preview.rows.single.existingId, existing.id);
      await service.saveSelectedWithRepository(
        MatchImportPreview(
          rows: [preview.rows.single.copyWith(selected: true)],
          warnings: const [],
        ),
        repository,
      );
      final updated = (await repository.get(existing.id))!;
      expect(updated.scoreA, 2);
      expect(updated.scoreB, 1);
      expect(updated.scoreDetail, '点球后结束');
      expect(updated.status, MatchStatuses.finished);
      expect(updated.favorite, isTrue);
      expect(updated.version, existing.version + 1);
    });
  }

  test('match audit explicit CSV result and false favorite update existing',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      status: MatchStatuses.finished,
      scoreA: 2,
      scoreB: 1,
      scoreDetail: '原结果',
      favorite: true,
    ));
    final service = MatchImportService();
    final preview = await service.previewCsvWithRepository(
      _csv(
          extraHeaders: ',状态,比分A,比分B,结果说明,收藏',
          extraValues: ',FINISHED,3,2,修正结果,false'),
      repository,
    );
    await service.saveSelectedWithRepository(
      MatchImportPreview(
          rows: [preview.rows.single.copyWith(selected: true)],
          warnings: const []),
      repository,
    );
    final updated = (await repository.get(existing.id))!;
    expect(updated.status, MatchStatuses.finished);
    expect(updated.scoreA, 3);
    expect(updated.scoreB, 2);
    expect(updated.scoreDetail, '修正结果');
    expect(updated.favorite, isFalse);
  });

  test('match audit explicit empty CSV fields can clear a result', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final existing = await repository.create(_draft().copyWith(
      status: MatchStatuses.finished,
      scoreA: 2,
      scoreB: 1,
      scoreDetail: '原结果',
      favorite: true,
    ));
    final service = MatchImportService();
    final preview = await service.previewCsvWithRepository(
      _csv(
          extraHeaders: ',状态,比分A,比分B,结果说明,收藏',
          extraValues: ',SCHEDULED,,,,false'),
      repository,
    );
    await service.saveSelectedWithRepository(
      MatchImportPreview(
          rows: [preview.rows.single.copyWith(selected: true)],
          warnings: const []),
      repository,
    );
    final updated = (await repository.get(existing.id))!;
    expect(updated.status, MatchStatuses.scheduled);
    expect(updated.scoreA, isNull);
    expect(updated.scoreB, isNull);
    expect(updated.scoreDetail, isNull);
    expect(updated.favorite, isFalse);
  });
}

MatchDraft _draft() => MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2099, 9, 7),
      startAt: DateTime.utc(2099, 9, 7, 12),
      timezoneId: 'Asia/Shanghai',
    );

String _csv(
        {String timezone = 'Asia/Shanghai',
        String extraHeaders = '',
        String extraValues = ''}) =>
    '运动类型,赛事,参赛方A,参赛方B,比赛日期,开始时间,时区$extraHeaders\n'
    '足球,英超,阿森纳,切尔西,2099-09-07,20:00,$timezone$extraValues';

String _ics(String uid) => '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:$uid
DTSTART;TZID=Asia/Shanghai:20990907T200000
DTEND;TZID=Asia/Shanghai:20990907T220000
SUMMARY:英超 阿森纳 vs 切尔西
END:VEVENT
END:VCALENDAR''';
