import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/reminder_operation_queue.dart';

const reminderTypeLabels = <String, String>{
  'TASK': '任务',
  'EVENT': '日程',
  'COURSE': '课程',
  'COURSE_SCHEDULE': '课程',
  'HABIT': '习惯',
  'ANNIVERSARY': '纪念日',
  'MEDICATION': '用药',
  'CREDENTIAL': '证件',
  'SUBSCRIPTION': '订阅',
  'HOUSEHOLD': '消耗品',
  'MAINTENANCE': '维护',
  'PARCEL': '快递',
  'MATCH': '比赛',
};

abstract interface class ReminderNotificationBridge {
  Future<void> cancelReminder(int notificationId);

  Future<void> scheduleReminder(ReminderEntry reminder, String title);
}

class ReminderView {
  const ReminderView({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.triggerAt,
    required this.enabled,
    required this.pastDue,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String title;
  final DateTime triggerAt;
  final bool enabled;
  final bool pastDue;

  String get typeLabel => reminderTypeLabels[entityType] ?? entityType;
}

class ReminderRepository {
  ReminderRepository(
    this._database, {
    this._notifications,
  });

  final AppDatabase _database;
  final ReminderNotificationBridge? _notifications;

  Future<List<ReminderView>> listWindow({
    required DateTime now,
    int days = 7,
    bool includeDisabled = false,
  }) async {
    final end = now.toUtc().add(Duration(days: days)).millisecondsSinceEpoch;
    final query = _database.select(_database.reminders)
      ..where((row) {
        var filter =
            row.deletedAt.isNull() &
            row.entityType.equals('MATCH').not() &
            row.triggerAt.isSmallerOrEqualValue(end);
        if (!includeDisabled) filter = filter & row.enabled.equals(true);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.triggerAt)]);
    final rows = await query.get();
    final result = <ReminderView>[];
    for (final row in rows) {
      final title = await _title(row.entityType, row.entityId);
      if (title == null) continue;
      final trigger = DateTime.fromMillisecondsSinceEpoch(
        row.triggerAt,
        isUtc: true,
      );
      result.add(
        ReminderView(
          id: row.id,
          entityType: row.entityType,
          entityId: row.entityId,
          title: title,
          triggerAt: trigger,
          enabled: row.enabled,
          pastDue: trigger.isBefore(now.toUtc()),
        ),
      );
    }
    return result;
  }

  Future<void> setEnabled(String id, bool enabled) =>
      ReminderOperationQueue.run(() => _setEnabled(id, enabled));

  Future<void> _setEnabled(String id, bool enabled) async {
    final current = await _get(id);
    if (current.entityType == 'MATCH') {
      throw StateError('比赛提醒由系统固定管理，不能修改。');
    }
    await (_database.update(
      _database.reminders,
    )..where((row) => row.id.equals(id))).write(
      RemindersCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        version: Value(current.version + 1),
      ),
    );
    final notifications = _notifications;
    if (notifications == null) return;
    if (!enabled) {
      await notifications.cancelReminder(current.notificationId);
      return;
    }
    final updated = await _get(id);
    final title = await _title(updated.entityType, updated.entityId);
    if (title != null) await notifications.scheduleReminder(updated, title);
  }

  Future<void> snooze(String id, DateTime triggerAt) =>
      ReminderOperationQueue.run(() => _snooze(id, triggerAt));

  Future<void> _snooze(String id, DateTime triggerAt) async {
    final current = await _get(id);
    if (current.entityType == 'MATCH') {
      throw StateError('比赛提醒由系统固定管理，不能稍后提醒。');
    }
    await (_database.update(
      _database.reminders,
    )..where((row) => row.id.equals(id))).write(
      RemindersCompanion(
        triggerAt: Value(triggerAt.toUtc().millisecondsSinceEpoch),
        enabled: const Value(true),
        metadata: Value(jsonEncode({'snoozed': true})),
        updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        version: Value(current.version + 1),
      ),
    );
    final notifications = _notifications;
    if (notifications != null) {
      final updated = await _get(id);
      final title = await _title(updated.entityType, updated.entityId);
      if (title != null) await notifications.scheduleReminder(updated, title);
    }
  }

  Future<ReminderEntry> _get(String id) async {
    final value =
        await (_database.select(_database.reminders)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (value == null) throw StateError('Reminder not found: $id');
    return value;
  }

  Future<String?> _title(String type, String id) async {
    switch (type) {
      case 'TASK':
        return (_database.select(_database.tasks)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.title)
            .getSingleOrNull();
      case 'EVENT':
        return (_database.select(_database.events)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.title)
            .getSingleOrNull();
      case 'COURSE':
        return (_database.select(_database.courses)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'COURSE_SCHEDULE':
        final schedule =
            await (_database.select(_database.courseSchedules)
                  ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
                .getSingleOrNull();
        if (schedule == null) return null;
        return (_database.select(_database.courses)..where(
              (row) =>
                  row.id.equals(schedule.courseId) & row.deletedAt.isNull(),
            ))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'HABIT':
        return (_database.select(_database.habits)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'MEDICATION':
        return (_database.select(_database.medicationPlans)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'CREDENTIAL':
        return (_database.select(_database.credentialRecords)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'ANNIVERSARY':
        return (_database.select(_database.anniversaries)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.title)
            .getSingleOrNull();
      case 'SUBSCRIPTION':
        return (_database.select(_database.subscriptions)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'HOUSEHOLD':
        return (_database.select(_database.householdItems)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.name)
            .getSingleOrNull();
      case 'MAINTENANCE':
        return (_database.select(_database.maintenancePlans)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.title)
            .getSingleOrNull();
      case 'PARCEL':
        return (_database.select(_database.parcels)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .map((row) => row.title)
            .getSingleOrNull();
      case 'MATCH':
        final match =
            await (_database.select(_database.matchRecords)
                  ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
                .getSingleOrNull();
        if (match == null) return null;
        return '${match.competition}：${match.participantA} vs ${match.participantB}';
      default:
        return null;
    }
  }
}
