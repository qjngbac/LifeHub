import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/reminder/data/reminder_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class _FakeNotifications implements ReminderNotificationBridge {
  final canceled = <int>[];
  final scheduled = <ReminderEntry>[];

  @override
  Future<void> cancelReminder(int notificationId) async {
    canceled.add(notificationId);
  }

  @override
  Future<void> scheduleReminder(ReminderEntry reminder, String title) async {
    scheduled.add(reminder);
  }
}

void main() {
  late AppDatabase database;
  late ReminderRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ReminderRepository(database);
  });

  tearDown(() => database.close());

  test('future reminders exclude deleted entities and resolve their titles',
      () async {
    final tasks = TaskRepository(database);
    final visible = await tasks.create(const TaskDraft(title: '明天交报告'));
    final deleted = await tasks.create(const TaskDraft(title: '已经删除'));
    await tasks.delete(deleted.id);
    final now = DateTime.utc(2026, 8, 9, 12);

    await database.into(database.reminders).insert(RemindersCompanion.insert(
          id: const Value('visible'),
          entityType: 'TASK',
          entityId: visible.id,
          triggerAt: now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
          notificationId: 101,
        ));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          id: const Value('deleted'),
          entityType: 'TASK',
          entityId: deleted.id,
          triggerAt: now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
          notificationId: 102,
        ));

    final result = await repository.listWindow(now: now);

    expect(result, hasLength(1));
    expect(result.single.title, '明天交报告');
    expect(result.single.missed, isFalse);
  });

  test('snooze moves the trigger and disabling hides it by default', () async {
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '喝水'));
    final now = DateTime.utc(2026, 8, 9, 12);
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          id: const Value('reminder'),
          entityType: 'TASK',
          entityId: task.id,
          triggerAt:
              now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          notificationId: 103,
        ));

    expect((await repository.listWindow(now: now)).single.missed, isTrue);
    final snoozed = now.add(const Duration(minutes: 20));
    await repository.snooze('reminder', snoozed);
    expect((await repository.listWindow(now: now)).single.triggerAt, snoozed);

    await repository.setEnabled('reminder', false);
    expect(await repository.listWindow(now: now), isEmpty);
    expect(
      await repository.listWindow(now: now, includeDisabled: true),
      hasLength(1),
    );
  });

  test('disable and snooze synchronize the Android notification bridge',
      () async {
    final notifications = _FakeNotifications();
    final synced = ReminderRepository(database, notifications: notifications);
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '同步提醒'));
    final now = DateTime.now().toUtc();
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          id: const Value('sync-reminder'),
          entityType: 'TASK',
          entityId: task.id,
          triggerAt: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
          notificationId: 501,
        ));

    await synced.setEnabled('sync-reminder', false);
    expect(notifications.canceled, [501]);

    final snoozed = now.add(const Duration(hours: 2));
    await synced.snooze('sync-reminder', snoozed);
    expect(notifications.scheduled, hasLength(1));
    expect(notifications.scheduled.single.triggerAt,
        snoozed.millisecondsSinceEpoch);
    expect(notifications.scheduled.single.metadata, contains('snoozed'));
  });
}
