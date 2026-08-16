import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_ids.dart';
import 'package:lifehub/core/notifications/notification_action_handler.dart';
import 'package:lifehub/core/notifications/notification_payload.dart';
import 'package:lifehub/core/notifications/v1_9_reminder_rules.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:lifehub/features/reminder/data/reminder_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final actionId = response.actionId;
  if (actionId == null || actionId.isEmpty) return;
  final database = AppDatabase();
  try {
    await NotificationActionHandler(database)
        .handle(actionId, response.payload);
    if (actionId == 'SNOOZE_10') {
      await NotificationService.instance
          ._rescheduleSnoozed(database, response.payload);
    }
  } finally {
    await database.close();
  }
}

class NotificationService implements ReminderNotificationBridge {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  AppDatabase? _actionDatabase;
  static const _focusNotificationId = 910001;

  void configureActions(AppDatabase database) {
    _actionDatabase = database;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) async {
        final database = _actionDatabase;
        final actionId = response.actionId;
        if (database == null || actionId == null || actionId.isEmpty) return;
        await NotificationActionHandler(database).handle(
          actionId,
          response.payload,
        );
        if (actionId == 'SNOOZE_10') {
          await _rescheduleSnoozed(database, response.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        true;
  }

  Future<void> showFocus({
    required int plannedMinutes,
    required bool paused,
  }) async {
    await initialize();
    await _plugin.show(
      id: _focusNotificationId,
      title: paused ? '专注已暂停' : 'LifeHub 专注中',
      body: '计划 $plannedMinutes 分钟 · 点击返回应用',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lifehub_focus',
          '专注计时',
          channelDescription: '显示正在进行的专注记录',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
        ),
      ),
      payload: 'FOCUS:ACTIVE',
    );
  }

  Future<void> cancelFocus() async {
    await initialize();
    await _plugin.cancel(id: _focusNotificationId);
  }

  Future<void> showFocusCompleted({required int plannedMinutes}) async {
    await initialize();
    await _plugin.show(
      id: _focusNotificationId,
      title: '专注完成',
      body: '已完成 $plannedMinutes 分钟专注，休息一下吧',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lifehub_focus',
          '专注计时',
          channelDescription: '显示正在进行和已经完成的专注记录',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: 'FOCUS:COMPLETED',
    );
  }

  @override
  Future<void> cancelReminder(int notificationId) async {
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<void> scheduleReminder(ReminderEntry reminder, String title) async {
    await initialize();
    final trigger = DateTime.fromMillisecondsSinceEpoch(
      reminder.triggerAt,
      isUtc: true,
    ).toLocal();
    if (!reminder.enabled || !trigger.isAfter(DateTime.now())) {
      await _plugin.cancel(id: reminder.notificationId);
      return;
    }
    await _schedulePlugin(
      id: reminder.notificationId,
      type: reminder.entityType,
      entityId: reminder.entityId,
      title: title,
      body: '稍后提醒',
      trigger: trigger,
    );
  }

  Future<void> _rescheduleSnoozed(
    AppDatabase database,
    String? payload,
  ) async {
    await initialize();
    final parsed = NotificationPayload.parse(payload);
    if (parsed == null) return;
    final type = parsed.type;
    final entityId = parsed.entityId;
    final reminder = await (database.select(database.reminders)
          ..where((row) {
            var filter = row.deletedAt.isNull() &
                row.enabled.equals(true) &
                row.entityType.equals(type) &
                row.entityId.equals(entityId);
            if (parsed.notificationId != null) {
              filter =
                  filter & row.notificationId.equals(parsed.notificationId!);
            }
            return filter;
          })
          ..orderBy([(row) => OrderingTerm(expression: row.triggerAt)])
          ..limit(1))
        .getSingleOrNull();
    if (reminder == null) return;
    final trigger = DateTime.fromMillisecondsSinceEpoch(
      reminder.triggerAt,
      isUtc: true,
    ).toLocal();
    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: 'LifeHub 稍后提醒',
      body: '你刚才选择了稍后 10 分钟',
      scheduledDate: tz.TZDateTime.from(trigger, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lifehub_reminders',
          'LifeHub 提醒',
          channelDescription: '任务、日程与课程提醒',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction('SNOOZE_10', '再稍后 10 分钟'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  Future<int> rebuildFuture(AppDatabase database) async {
    await initialize();
    final previous = await database.select(database.reminders).get();
    final previousByNotificationId = {
      for (final reminder in previous) reminder.notificationId: reminder,
    };
    final replacements = <RemindersCompanion>[];
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));
    var count = 0;
    final tasks = await (_activeTasks(database)).get();
    for (final task in tasks) {
      if (task.dueAt == null) continue;
      final due = DateTime.fromMillisecondsSinceEpoch(task.dueAt!, isUtc: true)
          .toLocal();
      if (due.isAfter(now) && due.isBefore(horizon)) {
        await _schedule(
          replacements,
          'TASK',
          task.id,
          task.title,
          '任务到期',
          due,
          previousByNotificationId,
        );
        count++;
      }
    }
    final events =
        await EventRepository(database).occurrencesWindow(now, horizon);
    for (final occurrence in events) {
      final trigger = occurrence.start.subtract(const Duration(minutes: 10));
      if (trigger.isAfter(now)) {
        await _schedule(
          replacements,
          'EVENT',
          occurrence.event.id,
          occurrence.event.title,
          '10 分钟后开始',
          trigger,
          previousByNotificationId,
        );
        count++;
      }
      if (occurrence.event.departureReminderEnabled &&
          !occurrence.event.allDay) {
        final departure = occurrence.start.subtract(Duration(
          minutes: occurrence.event.travelMinutes +
              occurrence.event.preparationMinutes,
        ));
        if (departure.isAfter(now)) {
          await _schedule(
            replacements,
            'EVENT',
            occurrence.event.id,
            occurrence.event.title,
            '现在应出发',
            departure,
            previousByNotificationId,
            kind: 'DEPARTURE',
          );
          count++;
        }
      }
    }
    final courses =
        await CourseRepository(database).projectedEvents(now, horizon);
    for (final course in courses) {
      final reminderMinutes = course.reminderMinutes ?? 10;
      final trigger = course.start.subtract(Duration(minutes: reminderMinutes));
      if (trigger.isAfter(now)) {
        await _schedule(
          replacements,
          'COURSE',
          course.courseId,
          course.title,
          '$reminderMinutes 分钟后上课',
          trigger,
          previousByNotificationId,
        );
        count++;
      }
    }
    final habits = await HabitRepository(database).list();
    final startDateKey = DateKeys.toLocalDateKey(now);
    final endDateKey =
        DateKeys.toLocalDateKey(now.add(const Duration(days: 13)));
    final completedLogs = await (database.select(database.habitLogs)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.localDate.isBetweenValues(startDateKey, endDateKey) &
              row.value.isBiggerThanValue(0)))
        .get();
    final completedDates =
        completedLogs.map((row) => '${row.habitId}:${row.localDate}').toSet();
    for (final habit in habits) {
      final parts = habit.reminderPolicy?.split(':');
      if (parts == null || parts.length != 2) continue;
      final hour = int.tryParse(parts.first);
      final minute = int.tryParse(parts.last);
      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        continue;
      }
      for (var offset = 0; offset < 14; offset++) {
        final date = DateTime(now.year, now.month, now.day + offset);
        if (!HabitRules.isScheduled(habit.scheduleRule, date)) continue;
        final dateKey = DateKeys.toLocalDateKey(date);
        if (completedDates.contains('${habit.id}:$dateKey')) continue;
        final trigger = DateTime(date.year, date.month, date.day, hour, minute);
        if (trigger.isAfter(now)) {
          await _schedule(
            replacements,
            'HABIT',
            habit.id,
            habit.name,
            '该完成今天的习惯了',
            trigger,
            previousByNotificationId,
          );
          count++;
        }
      }
    }
    final medicationPlans = await (database.select(database.medicationPlans)
          ..where((row) => row.deletedAt.isNull() & row.active.equals(true)))
        .get();
    final medicationLogs = await (database.select(database.medicationLogs)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.localDate.isBetweenValues(startDateKey, endDateKey)))
        .get();
    final medicationCheckIns = medicationLogs
        .map((row) => '${row.planId}:${row.localDate}:${row.timeMinutes}')
        .toSet();
    for (final plan in medicationPlans) {
      final rawTimes = jsonDecode(plan.reminderTimesJson) as List<dynamic>;
      for (var offset = 0; offset < 14; offset++) {
        final date = DateTime(now.year, now.month, now.day + offset);
        final dateKey = DateKeys.toLocalDateKey(date);
        if (dateKey < plan.startDate ||
            (plan.endDate != null && dateKey > plan.endDate!)) {
          continue;
        }
        for (final raw in rawTimes.cast<String>()) {
          final parts = raw.split(':');
          if (parts.length != 2) continue;
          final minutes =
              int.tryParse(parts[0]) == null || int.tryParse(parts[1]) == null
                  ? null
                  : int.parse(parts[0]) * 60 + int.parse(parts[1]);
          if (minutes == null ||
              medicationCheckIns.contains('${plan.id}:$dateKey:$minutes')) {
            continue;
          }
          final trigger = DateTime(
            date.year,
            date.month,
            date.day,
            minutes ~/ 60,
            minutes % 60,
          );
          if (trigger.isAfter(now)) {
            await _schedule(
              replacements,
              'MEDICATION',
              plan.id,
              plan.name,
              '这是你设置的记录提醒，请按自己的说明或专业医嘱处理',
              trigger,
              previousByNotificationId,
            );
            count++;
          }
        }
      }
    }
    final subscriptions = await (database.select(database.subscriptions)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ACTIVE')))
        .get();
    for (final subscription in subscriptions) {
      List<int> reminderDays;
      try {
        reminderDays = (jsonDecode(subscription.reminderDaysJson) as List)
            .whereType<num>()
            .map((value) => value.toInt())
            .toList();
      } on FormatException {
        reminderDays = const [7, 3, 1];
      }
      final renewal = DateKeys.fromLocalDateKey(subscription.nextRenewalDate);
      final triggers = V19ReminderRules.subscriptionTriggers(
        renewalDate: renewal,
        reminderDays: reminderDays,
      );
      for (var index = 0; index < triggers.length; index++) {
        final trigger = triggers[index];
        if (!trigger.isAfter(now) || !trigger.isBefore(horizon)) continue;
        await _schedule(
          replacements,
          'SUBSCRIPTION',
          subscription.id,
          subscription.name,
          '订阅即将续费，请确认是否继续',
          trigger,
          previousByNotificationId,
          kind: 'RENEWAL_$index',
        );
        count++;
      }
    }
    final consumables = await (database.select(database.householdItems)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.itemKind.equals('CONSUMABLE') &
              row.expiryDate.isNotNull()))
        .get();
    for (final item in consumables) {
      final trigger = V19ReminderRules.expiryTrigger(
        DateKeys.fromLocalDateKey(item.expiryDate!),
      );
      if (!trigger.isAfter(now) || !trigger.isBefore(horizon)) continue;
      await _schedule(
        replacements,
        'HOUSEHOLD',
        item.id,
        item.name,
        '消耗品将在 7 天内到期',
        trigger,
        previousByNotificationId,
        kind: 'EXPIRY',
      );
      count++;
    }
    final credentials = await (database.select(database.credentialRecords)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ACTIVE') &
              row.reminderDays.isBiggerOrEqualValue(0) &
              row.expiryDate.isNotNull()))
        .get();
    for (final credential in credentials) {
      final trigger = V19ReminderRules.expiryTrigger(
        DateKeys.fromLocalDateKey(credential.expiryDate!),
        daysBefore: credential.reminderDays,
      );
      if (!trigger.isAfter(now) || !trigger.isBefore(horizon)) continue;
      await _schedule(
        replacements,
        'CREDENTIAL',
        credential.id,
        credential.name,
        '证件将在 ${credential.reminderDays} 天后到期',
        trigger,
        previousByNotificationId,
        kind: 'EXPIRY',
      );
      count++;
    }
    final maintenancePlans = await (database.select(database.maintenancePlans)
          ..where((row) => row.deletedAt.isNull() & row.active.equals(true)))
        .get();
    for (final plan in maintenancePlans) {
      final trigger = V19ReminderRules.maintenanceTrigger(
        nextDueAt: DateTime.fromMillisecondsSinceEpoch(plan.nextDueAt),
        reminderDays: plan.reminderDays,
      );
      if (!trigger.isAfter(now) || !trigger.isBefore(horizon)) continue;
      await _schedule(
        replacements,
        'MAINTENANCE',
        plan.id,
        plan.title,
        '家庭物品维护即将到期',
        trigger,
        previousByNotificationId,
        kind: 'DUE',
      );
      count++;
    }
    final parcels = await (database.select(database.parcels)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('READY') &
              row.pickupDeadline.isNotNull()))
        .get();
    for (final parcel in parcels) {
      final trigger = V19ReminderRules.parcelTrigger(
        DateTime.fromMillisecondsSinceEpoch(parcel.pickupDeadline!),
      );
      if (!trigger.isAfter(now) || !trigger.isBefore(horizon)) continue;
      final message = V19ReminderRules.parcelMessage(
        title: parcel.title,
        trackingNumber: parcel.trackingNumber,
        pickupCode: parcel.pickupCode,
      );
      await _schedule(
        replacements,
        'PARCEL',
        parcel.id,
        message.title,
        message.body,
        trigger,
        previousByNotificationId,
        kind: 'PICKUP',
      );
      count++;
    }
    for (final reminder in previousByNotificationId.values) {
      if (!reminder.enabled ||
          !_isSnoozed(reminder) ||
          reminder.triggerAt <= now.toUtc().millisecondsSinceEpoch ||
          !await _entityStillExists(database, reminder)) {
        continue;
      }
      final trigger = DateTime.fromMillisecondsSinceEpoch(
        reminder.triggerAt,
        isUtc: true,
      ).toLocal();
      await _schedulePlugin(
        id: reminder.notificationId,
        type: reminder.entityType,
        entityId: reminder.entityId,
        title: 'LifeHub 稍后提醒',
        body: '你稍后的提醒已保留',
        trigger: trigger,
      );
      replacements.add(_existingReminderCompanion(reminder));
    }
    final newIds = replacements
        .map((row) => row.notificationId.value)
        .whereType<int>()
        .toSet();
    for (final reminder in previous) {
      if (!newIds.contains(reminder.notificationId)) {
        await _plugin.cancel(id: reminder.notificationId);
      }
    }
    await database.transaction(() async {
      await database.delete(database.reminders).go();
      for (final reminder in replacements) {
        await database.into(database.reminders).insert(reminder);
      }
    });
    return count;
  }

  SimpleSelectStatement<$TasksTable, TaskEntry> _activeTasks(
    AppDatabase database,
  ) =>
      database.select(database.tasks)
        ..where((row) =>
            row.deletedAt.isNull() &
            row.status.isNotIn([
              TaskStatus.done,
              TaskStatus.canceled,
              TaskStatus.archived,
            ]));

  Future<void> _schedule(
    List<RemindersCompanion> replacements,
    String type,
    String entityId,
    String title,
    String body,
    DateTime trigger,
    Map<int, ReminderEntry> previousByNotificationId, {
    String kind = 'DEFAULT',
  }) async {
    final milliseconds = trigger.toUtc().millisecondsSinceEpoch;
    final idType = kind == 'DEFAULT' ? type : '${type}_$kind';
    final id = NotificationIds.forOccurrence(idType, entityId, milliseconds);
    final previous = previousByNotificationId.remove(id);
    final enabled = previous?.enabled ?? true;
    final effectiveMilliseconds = previous != null && _isSnoozed(previous)
        ? previous.triggerAt
        : milliseconds;
    final effectiveTrigger = DateTime.fromMillisecondsSinceEpoch(
      effectiveMilliseconds,
      isUtc: true,
    ).toLocal();
    final primaryActions = switch (type) {
      'TASK' => const [
          AndroidNotificationAction('TASK_DONE', '完成'),
        ],
      'HABIT' => const [
          AndroidNotificationAction('HABIT_DONE', '打卡'),
        ],
      _ => const <AndroidNotificationAction>[],
    };
    final actions = [
      ...primaryActions,
      const AndroidNotificationAction('SNOOZE_10', '稍后 10 分钟'),
    ];
    if (enabled) {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(effectiveTrigger, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'lifehub_reminders',
            'LifeHub 提醒',
            channelDescription: '任务、日程与课程提醒',
            importance: Importance.high,
            priority: Priority.high,
            actions: actions,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: NotificationPayload(
          type: type,
          entityId: entityId,
          notificationId: id,
        ).encode(),
      );
    } else {
      await _plugin.cancel(id: id);
    }
    replacements.add(RemindersCompanion.insert(
      id: previous == null ? const Value.absent() : Value(previous.id),
      entityType: type,
      entityId: entityId,
      triggerAt: effectiveMilliseconds,
      notificationId: id,
      enabled: Value(enabled),
      reminderKind: Value(kind),
      createdAt:
          previous == null ? const Value.absent() : Value(previous.createdAt),
      updatedAt:
          previous == null ? const Value.absent() : Value(previous.updatedAt),
      version:
          previous == null ? const Value.absent() : Value(previous.version),
      metadata:
          previous == null ? const Value.absent() : Value(previous.metadata),
    ));
  }

  bool _isSnoozed(ReminderEntry reminder) {
    try {
      final metadata = jsonDecode(reminder.metadata);
      return metadata is Map && metadata['snoozed'] == true;
    } on FormatException {
      return false;
    }
  }

  RemindersCompanion _existingReminderCompanion(ReminderEntry reminder) =>
      RemindersCompanion.insert(
        id: Value(reminder.id),
        entityType: reminder.entityType,
        entityId: reminder.entityId,
        triggerAt: reminder.triggerAt,
        notificationId: reminder.notificationId,
        enabled: Value(reminder.enabled),
        reminderKind: Value(reminder.reminderKind),
        createdAt: Value(reminder.createdAt),
        updatedAt: Value(reminder.updatedAt),
        version: Value(reminder.version),
        deletedAt: Value(reminder.deletedAt),
        syncState: Value(reminder.syncState),
        metadata: Value(reminder.metadata),
      );

  Future<bool> _entityStillExists(
    AppDatabase database,
    ReminderEntry reminder,
  ) async {
    switch (reminder.entityType) {
      case 'TASK':
        return await (_activeTasks(database)
                  ..where((row) => row.id.equals(reminder.entityId)))
                .getSingleOrNull() !=
            null;
      case 'EVENT':
        return await (database.select(database.events)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.archived.equals(false)))
                .getSingleOrNull() !=
            null;
      case 'COURSE':
        return await (database.select(database.courses)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull()))
                .getSingleOrNull() !=
            null;
      case 'HABIT':
        return await (database.select(database.habits)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.active.equals(true)))
                .getSingleOrNull() !=
            null;
      case 'MEDICATION':
        return await (database.select(database.medicationPlans)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.active.equals(true)))
                .getSingleOrNull() !=
            null;
      case 'SUBSCRIPTION':
        return await (database.select(database.subscriptions)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.status.equals('ACTIVE')))
                .getSingleOrNull() !=
            null;
      case 'HOUSEHOLD':
        return await (database.select(database.householdItems)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.status.equals('ARCHIVED').not()))
                .getSingleOrNull() !=
            null;
      case 'MAINTENANCE':
        return await (database.select(database.maintenancePlans)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.active.equals(true)))
                .getSingleOrNull() !=
            null;
      case 'PARCEL':
        return await (database.select(database.parcels)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.status.equals('READY')))
                .getSingleOrNull() !=
            null;
      case 'CREDENTIAL':
        return await (database.select(database.credentialRecords)
                  ..where((row) =>
                      row.id.equals(reminder.entityId) &
                      row.deletedAt.isNull() &
                      row.status.equals('ACTIVE') &
                      row.reminderDays.isBiggerOrEqualValue(0) &
                      row.expiryDate.isNotNull()))
                .getSingleOrNull() !=
            null;
      default:
        return false;
    }
  }

  Future<void> _schedulePlugin({
    required int id,
    required String type,
    required String entityId,
    required String title,
    required String body,
    required DateTime trigger,
  }) async {
    final primaryActions = switch (type) {
      'TASK' => const [
          AndroidNotificationAction('TASK_DONE', '完成'),
        ],
      'HABIT' => const [
          AndroidNotificationAction('HABIT_DONE', '打卡'),
        ],
      _ => const <AndroidNotificationAction>[],
    };
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(trigger, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'lifehub_reminders',
          'LifeHub 提醒',
          channelDescription: '任务、日程与课程提醒',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            ...primaryActions,
            const AndroidNotificationAction(
              'SNOOZE_10',
              '稍后 10 分钟',
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: NotificationPayload(
        type: type,
        entityId: entityId,
        notificationId: id,
      ).encode(),
    );
  }
}
