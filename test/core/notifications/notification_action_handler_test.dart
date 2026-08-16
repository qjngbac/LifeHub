import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_action_handler.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  test('task and habit actions are idempotent while event is open-only',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '完成我'));
    final habit =
        await HabitRepository(database).create(const HabitDraft(name: '喝水'));
    final handler = NotificationActionHandler(database);
    final now = DateTime(2026, 8, 9, 9);

    await handler.handle('TASK_DONE', 'TASK:${task.id}', now: now);
    await handler.handle('TASK_DONE', 'TASK:${task.id}', now: now);
    expect(
        (await TaskRepository(database).get(task.id)).status, TaskStatus.done);

    await handler.handle('HABIT_DONE', 'HABIT:${habit.id}', now: now);
    await handler.handle('HABIT_DONE', 'HABIT:${habit.id}', now: now);
    expect(await HabitRepository(database).logs(habit.id), hasLength(1));

    expect(
      await handler.handle('TASK_DONE', 'EVENT:any', now: now),
      NotificationActionResult.openOnly,
    );
  });

  test('snooze moves an existing reminder ten minutes and is idempotent',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '稍后提醒'));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          entityType: 'TASK',
          entityId: task.id,
          triggerAt: DateTime(2026, 8, 9, 9).millisecondsSinceEpoch,
          notificationId: 101,
        ));
    final now = DateTime(2026, 8, 9, 10);
    final handler = NotificationActionHandler(database);

    await handler.handle('SNOOZE_10', 'TASK:${task.id}', now: now);
    await handler.handle('SNOOZE_10', 'TASK:${task.id}', now: now);

    final reminder = await database.select(database.reminders).getSingle();
    expect(
      reminder.triggerAt,
      now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    );
  });

  test('snooze payload targets the exact occurrence notification', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.events).insert(EventsCompanion.insert(
          id: const Value('event-with-two-reminders'),
          title: '需要出发提醒的日程',
          startAt: DateTime(2026, 8, 9, 12).millisecondsSinceEpoch,
          endAt: DateTime(2026, 8, 9, 13).millisecondsSinceEpoch,
        ));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          entityType: 'EVENT',
          entityId: 'event-with-two-reminders',
          triggerAt: DateTime(2026, 8, 9, 9).millisecondsSinceEpoch,
          notificationId: 101,
          reminderKind: const Value('DEFAULT'),
        ));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          entityType: 'EVENT',
          entityId: 'event-with-two-reminders',
          triggerAt: DateTime(2026, 8, 9, 10).millisecondsSinceEpoch,
          notificationId: 102,
          reminderKind: const Value('DEPARTURE'),
        ));
    final now = DateTime(2026, 8, 9, 11);

    await NotificationActionHandler(database).handle(
      'SNOOZE_10',
      'EVENT:event-with-two-reminders|102',
      now: now,
    );

    final rows = await database.select(database.reminders).get();
    final byId = {for (final row in rows) row.notificationId: row};
    expect(
      byId[101]!.triggerAt,
      DateTime(2026, 8, 9, 9).millisecondsSinceEpoch,
    );
    expect(
      byId[102]!.triggerAt,
      now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    );
  });
}
