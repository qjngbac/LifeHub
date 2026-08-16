import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';

void main() {
  late AppDatabase database;
  late HabitRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HabitRepository(database);
  });

  tearDown(() => database.close());

  test('checking in twice on one date updates one log', () async {
    final habit = await repository.create(const HabitDraft(name: '阅读'));
    final date = DateTime(2026, 8, 8);

    await repository.checkIn(habit.id, date, value: 1);
    await repository.checkIn(habit.id, date, value: 2);

    final logs = await repository.logs(habit.id);
    expect(logs, hasLength(1));
    expect(logs.single.value, 2);
  });
  test('streak and weekly progress are derived from logs', () async {
    final habit = await repository.create(const HabitDraft(name: '阅读'));
    await repository.checkIn(habit.id, DateTime(2026, 8, 6));
    await repository.checkIn(habit.id, DateTime(2026, 8, 7));
    await repository.checkIn(habit.id, DateTime(2026, 8, 8));

    expect(await repository.streak(habit.id, DateTime(2026, 8, 8)), 3);
    expect(
      await repository.weeklyProgress(habit.id, DateTime(2026, 8, 8)),
      closeTo(3 / 7, 0.001),
    );
  });

  test('habit can be updated and archived', () async {
    final habit = await repository.create(const HabitDraft(name: 'old'));
    final updated = await repository.update(
      habit.id,
      const HabitDraft(
        name: 'new',
        scheduleRule: 'WEEKDAYS',
        targetCount: 2,
        reminderPolicy: '20:30',
      ),
    );
    expect(updated.name, 'new');
    expect(updated.targetCount, 2);
    await repository.archive(habit.id);
    expect(await repository.list(), isEmpty);
  });

  test('archived habit can be restored and deleted habit stays hidden',
      () async {
    final habit = await repository.create(const HabitDraft(name: '阅读'));
    await repository.archive(habit.id);
    expect((await repository.list(activeOnly: false)).single.active, isFalse);

    await repository.restore(habit.id);
    expect((await repository.list()).single.active, isTrue);

    await repository.delete(habit.id);
    expect(await repository.list(activeOnly: false), isEmpty);
  });
}
