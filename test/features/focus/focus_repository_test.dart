import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/focus/application/focus_clock.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';

void main() {
  late AppDatabase database;
  late FocusRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FocusRepository(database);
  });
  tearDown(() => database.close());

  test('only one active session is allowed and pause time is excluded',
      () async {
    final start = DateTime.utc(2026, 8, 9, 9);
    final session = await repository.start(
      const FocusDraft(plannedMinutes: 45),
      now: start,
    );
    await expectLater(
      repository.start(const FocusDraft(plannedMinutes: 25), now: start),
      throwsStateError,
    );
    await repository.pause(
      session.id,
      now: start.add(const Duration(minutes: 10)),
    );
    await repository.resume(
      session.id,
      now: start.add(const Duration(minutes: 15)),
    );
    final finished = await repository.finish(
      session.id,
      now: start.add(const Duration(minutes: 30)),
    );

    expect(finished.actualMinutes, 25);
    expect(await repository.active(), isNull);
  });

  test('focus clock restores elapsed time from persisted timestamps', () async {
    final start = DateTime.utc(2026, 8, 9, 9);
    final session = await repository.start(
      const FocusDraft(plannedMinutes: 45),
      now: start,
    );
    expect(
      FocusClock.elapsed(
        session,
        start.add(const Duration(minutes: 12)),
      ),
      const Duration(minutes: 12),
    );
  });

  test('concurrent start calls still create only one active session', () async {
    final results = await Future.wait(
      [
        repository.start(const FocusDraft(plannedMinutes: 25)),
        repository.start(const FocusDraft(plannedMinutes: 45)),
      ].map((future) async {
        try {
          await future;
          return true;
        } on StateError {
          return false;
        }
      }),
    );

    expect(results.where((value) => value), hasLength(1));
    final rows = await database.select(database.focusSessions).get();
    expect(rows.where((value) => value.status == FocusStatus.running),
        hasLength(1));
  });

  test('finishIfDue ends at the planned deadline and is idempotent', () async {
    final start = DateTime.utc(2026, 8, 9, 9);
    final session = await repository.start(
      const FocusDraft(plannedMinutes: 37),
      now: start,
    );

    expect(
      await repository.finishIfDue(
        session.id,
        now: start.add(const Duration(minutes: 36, seconds: 59)),
      ),
      isNull,
    );
    final finished = await repository.finishIfDue(
      session.id,
      now: start.add(const Duration(minutes: 40)),
    );
    final again = await repository.finishIfDue(
      session.id,
      now: start.add(const Duration(minutes: 50)),
    );

    expect(finished?.actualMinutes, 37);
    expect(again?.id, finished?.id);
    expect(again?.endedAt, finished?.endedAt);
  });

  test('stopwatch counts upward and never auto finishes', () async {
    final start = DateTime.utc(2026, 8, 9, 9);
    final session = await repository.start(
      const FocusDraft(
        plannedMinutes: 0,
        mode: FocusMode.stopwatch,
      ),
      now: start,
    );

    expect(session.mode, FocusMode.stopwatch);
    expect(
      FocusClock.elapsed(session, start.add(const Duration(hours: 3))),
      const Duration(hours: 3),
    );
    expect(
      await repository.finishIfDue(
        session.id,
        now: start.add(const Duration(days: 2)),
      ),
      isNull,
    );
    expect((await repository.active())?.id, session.id);
  });
}
