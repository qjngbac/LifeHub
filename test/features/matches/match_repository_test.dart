import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';

MatchDraft validFutureDraft(String suffix) => MatchDraft(
      sportType: '足球',
      competition: '联赛',
      participantA: '主队 $suffix',
      participantB: '客队 $suffix',
      matchDate: DateTime(2026, 9, 20),
      startAt: DateTime.utc(2026, 9, 20, 12),
      timezoneId: 'Asia/Shanghai',
      sourceType: MatchSources.manual,
    );

void main() {
  late AppDatabase database;
  late MatchRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MatchRepository(database);
  });

  tearDown(() => database.close());

  test('fresh database creates match_records and schema 12', () async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'match_records'",
        )
        .get();
    expect(rows, hasLength(1));
    expect(database.schemaVersion, 13);
  });

  test('batch creation is all-or-nothing', () async {
    final drafts = [validFutureDraft('a'), const MatchDraft()];
    await expectLater(
        repository.createBatch(drafts), throwsA(isA<FormatException>()));
    expect(await database.select(database.matchRecords).get(), isEmpty);
  });

  test('import batch rejects duplicate writes without partial persistence',
      () async {
    final draft = validFutureDraft('duplicate');

    await expectLater(
      repository.importBatch([
        (draft: draft, existingId: null),
        (draft: draft.copyWith(notes: 'same match'), existingId: null),
      ]),
      throwsA(isA<FormatException>()),
    );

    expect(await database.select(database.matchRecords).get(), isEmpty);
  });

  test('import batch rejects repeated stable source keys', () async {
    final first = validFutureDraft('first').copyWith(sourceKey: 'source-1');
    final second = validFutureDraft('second').copyWith(sourceKey: 'source-1');

    await expectLater(
      repository.importBatch([
        (draft: first, existingId: null),
        (draft: second, existingId: null),
      ]),
      throwsA(isA<FormatException>()),
    );

    expect(await database.select(database.matchRecords).get(), isEmpty);
  });

  test('same source key is a possible duplicate', () async {
    final first = await repository.create(
      validFutureDraft('a').copyWith(sourceKey: 'source-1'),
    );
    final duplicates = await repository.findPossibleDuplicates(
      validFutureDraft('b').copyWith(sourceKey: 'source-1'),
    );
    expect(duplicates.map((item) => item.id), contains(first.id));
  });

  test('due scheduled match moves to pending result', () async {
    final draft = validFutureDraft('a').copyWith(
      matchDate: DateTime(2026, 9, 7),
      startAt: DateTime.utc(2026, 9, 7, 12),
    );
    final row = await repository.create(draft);
    await repository.markDuePending(DateTime.utc(2026, 9, 7, 12));
    expect((await repository.get(row.id))!.status, MatchStatuses.pendingResult);
  });

  test('record result requires a pair and finishes match', () async {
    final row = await repository.create(validFutureDraft('a'));
    await expectLater(
      repository.recordResult(row.id, scoreA: 1),
      throwsA(isA<FormatException>()),
    );
    final finished =
        await repository.recordResult(row.id, scoreA: 2, scoreB: 1);
    expect(finished.status, MatchStatuses.finished);
  });

  test('postponing clears the old time until a new time is confirmed',
      () async {
    final row = await repository.create(validFutureDraft('a'));
    final postponed = await repository.postpone(row.id);
    expect(postponed.status, MatchStatuses.postponed);
    expect(postponed.startAt, isNull);
    expect(postponed.timezoneId, isNull);
  });

  test('editing a match to postponed also clears its stale time', () async {
    final row = await repository.create(validFutureDraft('a'));
    final postponed = await repository.update(
      row.id,
      validFutureDraft('a').copyWith(status: MatchStatuses.postponed),
    );
    expect(postponed.status, MatchStatuses.postponed);
    expect(postponed.startAt, isNull);
    expect(postponed.timezoneId, isNull);
  });

  test('each tab query applies its supported filters', () async {
    await repository.create(validFutureDraft('a').copyWith(
      matchDate: DateTime(2099, 9, 20),
      startAt: DateTime.utc(2099, 9, 20, 12),
    ));
    await repository.create(MatchDraft(
      sportType: '篮球',
      competition: 'CBA',
      participantA: '北京',
      participantB: '上海',
      matchDate: DateTime(2099, 9, 21),
      startAt: DateTime.utc(2099, 9, 21, 12),
      timezoneId: 'Asia/Shanghai',
    ));
    await repository.create(validFutureDraft('pending').copyWith(
      matchDate: DateTime(2099, 9, 22),
      startAt: DateTime.utc(2099, 9, 22, 12),
      status: MatchStatuses.pendingResult,
    ));
    await repository.create(MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2025, 9, 7),
      scoreA: 2,
      scoreB: 1,
      status: MatchStatuses.finished,
    ));

    expect(
      await repository.listUpcoming(
        now: DateTime(2099, 1, 1),
        sportType: '足球',
        competition: '联赛',
        from: DateTime(2099, 9, 20),
        to: DateTime(2099, 9, 20),
      ),
      hasLength(1),
    );
    expect(
      await repository.listPendingResults(
        now: DateTime(2099, 1, 1),
        sportType: '足球',
        competition: '联赛',
        from: DateTime(2099, 9, 22),
        to: DateTime(2099, 9, 22),
      ),
      hasLength(1),
    );
    expect(
      await repository.listArchive(
        year: 2025,
        sportType: '足球',
        competition: '英超',
        status: MatchStatuses.finished,
      ),
      hasLength(1),
    );
  });

  test('getSuggestions collects sportTypes, competitions and participants',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    await repository.create(MatchDraft(
      sportType: '网球',
      competition: '温网',
      participantA: '费德勒',
      participantB: '纳达尔',
      matchDate: DateTime(2025, 7, 6),
      scoreA: 3,
      scoreB: 2,
      status: MatchStatuses.finished,
    ));

    final suggestions = await repository.getSuggestions();
    expect(suggestions.sportTypes, contains('网球'));
    expect(suggestions.competitions, contains('温网'));
    expect(suggestions.participants, contains('费德勒'));
    expect(suggestions.participants, contains('纳达尔'));
    expect(suggestions.competitionsFor('网球'), contains('温网'));
    expect(suggestions.participantsFor('网球'), contains('费德勒'));
  });
}
