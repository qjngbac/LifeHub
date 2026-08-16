import 'dart:convert';

import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:drift/drift.dart';
import 'package:lifehub/core/notifications/notification_payload.dart';

enum NotificationActionResult { handled, openOnly, ignored }

class NotificationActionHandler {
  NotificationActionHandler(this._database);
  final AppDatabase _database;

  Future<NotificationActionResult> handle(
    String actionId,
    String? payload, {
    DateTime? now,
  }) async {
    final parsed = NotificationPayload.parse(payload);
    if (parsed == null) return NotificationActionResult.ignored;
    final type = parsed.type;
    final id = parsed.entityId;
    if (actionId == 'SNOOZE_10') {
      final reminder = await (_database.select(_database.reminders)
            ..where((row) {
              var filter = row.deletedAt.isNull() &
                  row.enabled.equals(true) &
                  row.entityType.equals(type) &
                  row.entityId.equals(id);
              if (parsed.notificationId != null) {
                filter =
                    filter & row.notificationId.equals(parsed.notificationId!);
              }
              return filter;
            })
            ..orderBy([(row) => OrderingTerm(expression: row.triggerAt)])
            ..limit(1))
          .getSingleOrNull();
      if (reminder == null) return NotificationActionResult.ignored;
      final trigger = (now ?? DateTime.now())
          .add(const Duration(minutes: 10))
          .toUtc()
          .millisecondsSinceEpoch;
      await (_database.update(_database.reminders)
            ..where((row) => row.id.equals(reminder.id)))
          .write(RemindersCompanion(
        triggerAt: Value(trigger),
        enabled: const Value(true),
        metadata: Value(jsonEncode({'snoozed': true})),
        updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        version: Value(reminder.version + 1),
      ));
      return NotificationActionResult.handled;
    }
    if (type == 'EVENT' || type == 'COURSE') {
      return NotificationActionResult.openOnly;
    }
    if (actionId == 'TASK_DONE' && type == 'TASK') {
      final repository = TaskRepository(_database);
      final task = await repository.get(id);
      if (task.deletedAt == null && task.status != TaskStatus.done) {
        await repository.setStatus(id, TaskStatus.done);
      }
      return NotificationActionResult.handled;
    }
    if (actionId == 'HABIT_DONE' && type == 'HABIT') {
      final repository = HabitRepository(_database);
      final habit = await repository.get(id);
      if (habit.deletedAt == null) {
        await repository.checkIn(
          id,
          now ?? DateTime.now(),
          value: habit.targetCount,
        );
      }
      return NotificationActionResult.handled;
    }
    return NotificationActionResult.openOnly;
  }
}
