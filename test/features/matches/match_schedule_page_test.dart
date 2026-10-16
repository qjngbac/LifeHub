import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/presentation/match_dialogs.dart';
import 'package:lifehub/features/matches/presentation/match_schedule_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('match page exposes three states and upcoming cards',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MatchRepository(database).create(MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2099, 9, 7),
      startAt: DateTime(2099, 9, 7, 20),
      timezoneId: 'Asia/Shanghai',
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MatchSchedulePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('比赛日程'), findsOneWidget);
    expect(find.text('即将开始'), findsOneWidget);
    expect(find.text('待补结果'), findsOneWidget);
    expect(find.text('赛事档案'), findsOneWidget);
    expect(find.text('阿森纳'), findsOneWidget);
    expect(find.text('切尔西'), findsOneWidget);
  });

  testWidgets('archive groups match cards by year then sport and competition',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    for (final draft in [
      MatchDraft(
        sportType: '足球',
        competition: '英超',
        participantA: '阿森纳',
        participantB: '切尔西',
        matchDate: DateTime(2025, 9, 7),
        scoreA: 2,
        scoreB: 1,
        status: MatchStatuses.finished,
      ),
      MatchDraft(
        sportType: '足球',
        competition: '西甲',
        participantA: '皇马',
        participantB: '巴萨',
        matchDate: DateTime(2025, 9, 9),
        scoreA: 3,
        scoreB: 2,
        status: MatchStatuses.finished,
      ),
      MatchDraft(
        sportType: '篮球',
        competition: 'CBA',
        participantA: '北京',
        participantB: '上海',
        matchDate: DateTime(2025, 9, 8),
        scoreA: 100,
        scoreB: 98,
        status: MatchStatuses.finished,
      ),
    ]) {
      await repository.create(draft);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MatchSchedulePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('赛事档案'));
    await tester.pumpAndSettle();

    expect(find.text('2025 年 · 3 场'), findsOneWidget);
    expect(find.text('足球'), findsOneWidget);
    expect(find.text('篮球'), findsOneWidget);
    await tester.tap(find.text('足球'));
    await tester.pumpAndSettle();
    expect(find.text('英超'), findsOneWidget);
    expect(find.text('西甲'), findsOneWidget);
  });

  testWidgets('quick result rebuilds reminders and refreshes pending results',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
    final row = await repository.create(MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2026, 9, 7),
      startAt: DateTime.utc(2026, 9, 7, 12),
      timezoneId: 'Asia/Shanghai',
      status: MatchStatuses.pendingResult,
    ));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          entityType: 'MATCH',
          entityId: row.id,
          triggerAt: DateTime.utc(2026, 9, 7, 11).millisecondsSinceEpoch,
          notificationId: 31001,
          reminderKind: const Value('BEFORE_1H'),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        home: MatchSchedulePage(
          rebuildNotifications: (database) =>
              database.delete(database.reminders).go(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待补结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('补录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '比分 A'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '比分 B'),
      '1',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect((await repository.get(row.id))!.status, MatchStatuses.finished);
    expect(await database.select(database.reminders).get(), isEmpty);
    expect(find.text('阿森纳'), findsNothing);
    expect(find.text('暂无待补结果的比赛'), findsOneWidget);
  });

  testWidgets('pending result record opens the edit dialog without crashing',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final row = await MatchRepository(database).create(MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2026, 9, 7),
      startAt: DateTime.utc(2026, 9, 8),
      timezoneId: 'America/New_York',
      status: MatchStatuses.pendingResult,
    ));
    MatchDraft? edited;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              edited = await showMatchDraftDialog(context, current: row);
            },
            child: const Text('编辑待补比赛'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('编辑待补比赛'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('编辑比赛'), findsOneWidget);
    expect(find.text('待补结果'), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(edited!.status, MatchStatuses.pendingResult);
    expect(edited!.startAt, DateTime.utc(2026, 9, 8));
    expect(edited!.timezoneId, 'America/New_York');
  });

  testWidgets('match card renders start time in the declared timezone',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MatchRepository(database).create(MatchDraft(
      sportType: '篮球',
      competition: '美职篮',
      participantA: '纽约',
      participantB: '迈阿密',
      matchDate: DateTime(2027, 9, 7),
      startAt: DateTime.utc(2027, 9, 8),
      timezoneId: 'America/New_York',
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MatchSchedulePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('2027年9月7日 20:00'), findsOneWidget);
  });

  testWidgets('postponing a match rebuilds reminders', (tester) async {
    await _expectDetailMutationRebuildsReminders(
      tester,
      actionLabel: '延期比赛',
      expectedStatus: MatchStatuses.postponed,
    );
  });

  testWidgets('cancelling a match rebuilds reminders', (tester) async {
    await _expectDetailMutationRebuildsReminders(
      tester,
      actionLabel: '取消比赛',
      expectedStatus: MatchStatuses.cancelled,
    );
  });

  testWidgets('deleting a match rebuilds reminders', (tester) async {
    await _expectDetailMutationRebuildsReminders(
      tester,
      actionLabel: '删除',
      deleted: true,
    );
  });

  testWidgets('archive shows team stats banner when queried', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MatchRepository(database);
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
    await repository.create(MatchDraft(
      sportType: '足球',
      competition: '欧冠',
      participantA: '巴萨',
      participantB: '阿森纳',
      matchDate: DateTime(2025, 8, 1),
      scoreA: 0,
      scoreB: 1,
      status: MatchStatuses.finished,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MatchSchedulePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('赛事档案'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '阿森纳');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('“阿森纳” 战绩看板'), findsOneWidget);
    expect(find.text('胜率 100.0%'), findsOneWidget);
    expect(find.text('战绩：2 胜 0 平 0 负'), findsOneWidget);
  });

  testWidgets('swap button exchanges participant A and B in draft dialog',
      (tester) async {
    MatchDraft? savedDraft;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              savedDraft = await showMatchDraftDialog(
                context,
                initial: MatchDraft(
                  sportType: '足球',
                  competition: '英超',
                  participantA: '主队',
                  participantB: '客队',
                  matchDate: DateTime(2026, 9, 7),
                  startAt: DateTime.utc(2026, 9, 7, 12),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('主队'), findsOneWidget);
    expect(find.text('客队'), findsOneWidget);

    await tester.tap(find.byTooltip('主客对调'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedDraft, isNotNull);
    expect(savedDraft!.participantA, '客队');
    expect(savedDraft!.participantB, '主队');
  });

  testWidgets(
      'draft dialog cascades competition and participant suggestions by sport',
      (tester) async {
    const suggestions = MatchSuggestions(
      sportTypes: ['足球', '篮球'],
      competitions: ['英超', 'NBA'],
      participants: ['阿森纳', '湖人'],
      competitionsBySport: {
        '足球': ['英超'],
        '篮球': ['NBA'],
      },
      participantsBySport: {
        '足球': ['阿森纳'],
        '篮球': ['湖人'],
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMatchDraftDialog(
              context,
              suggestions: suggestions,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('英超'), findsOneWidget);
    expect(find.text('阿森纳'), findsOneWidget);
    expect(find.text('NBA'), findsNothing);

    await tester.tap(find.text('篮球'));
    await tester.pumpAndSettle();

    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('湖人'), findsOneWidget);
    expect(find.text('英超'), findsNothing);
  });
}

Future<void> _expectDetailMutationRebuildsReminders(
  WidgetTester tester, {
  required String actionLabel,
  String? expectedStatus,
  bool deleted = false,
}) async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = MatchRepository(database);
  final row = await repository.create(MatchDraft(
    sportType: '足球',
    competition: '英超',
    participantA: '阿森纳',
    participantB: '切尔西',
    matchDate: DateTime(2027, 9, 7),
    startAt: DateTime.utc(2027, 9, 7, 12),
    timezoneId: 'Asia/Shanghai',
  ));
  await database.into(database.reminders).insert(RemindersCompanion.insert(
        entityType: 'MATCH',
        entityId: row.id,
        triggerAt: DateTime.utc(2027, 9, 7, 11).millisecondsSinceEpoch,
        notificationId: 32001,
        reminderKind: const Value('BEFORE_1H'),
      ));
  var rebuildCount = 0;
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: MaterialApp(
      home: MatchSchedulePage(
        rebuildNotifications: (database) async {
          rebuildCount++;
          await database.delete(database.reminders).go();
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('阿森纳'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();

  expect(rebuildCount, 1);
  expect(await database.select(database.reminders).get(), isEmpty);
  final saved = await repository.get(row.id);
  if (deleted) {
    expect(saved, isNull);
  } else {
    expect(saved!.status, expectedStatus);
  }
}
