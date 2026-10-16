import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart'
    show Value, QueryInterceptor, QueryExecutor, ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/backup/background_backup_scheduler.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_ids.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/reminder/data/reminder_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart' hide TaskStatus;

class _Workmanager extends WorkmanagerPlatform {
  final tasks = <String, Duration?>{};
  @override
  Future<void> cancelByUniqueName(String name) async => tasks.remove(name);
  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    tasks[taskName] = frequency;
  }
}

class _DuringPlanning extends QueryInterceptor {
  Future<void> Function()? action;
  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM "match_records"') && action != null) {
      final callback = action!;
      action = null;
      await callback();
    }
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = NotificationService.instance;
  late AppDatabase database;
  late Map<int, Map<dynamic, dynamic>> pending;
  Future<void> Function(Map<dynamic, dynamic>)? onSchedule;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service.configureActions(database);
    SharedPreferences.setMockInitialValues({});
    pending = {};
    onSchedule = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'zonedSchedule') {
        final args = call.arguments as Map<dynamic, dynamic>;
        pending[args['id'] as int] = args;
        final callback = onSchedule;
        if (callback != null) await callback(args);
      }
      if (call.method == 'cancel') {
        pending.remove((call.arguments as Map)['id']);
      }
      return null;
    });
  });
  tearDown(() async {
    await database.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<TaskEntry> seedTask({String title = 'Task'}) =>
      TaskRepository(database).create(TaskDraft(
          title: title, dueAt: DateTime.now().add(const Duration(days: 1))));

  Future<ReminderEntry> seedReminder(TaskEntry task,
          {int? triggerAt, String metadata = '{}'}) =>
      database
          .into(database.reminders)
          .insertReturning(RemindersCompanion.insert(
            entityType: 'TASK',
            entityId: task.id,
            triggerAt: triggerAt ?? task.dueAt!,
            notificationId:
                NotificationIds.forOccurrence('TASK', task.id, task.dueAt!),
            metadata: Value(metadata),
          ));

  test(
      'expired snooze falls back to the future occurrence without losing later reminders',
      () async {
    final task = await seedTask();
    await seedReminder(task,
        triggerAt: DateTime.now()
            .subtract(const Duration(minutes: 20))
            .millisecondsSinceEpoch,
        metadata: '{"snoozed":true,"other":"keep"}');
    await seedTask(title: 'Later task');
    await service.rebuildFuture(database);
    final rows = await database.select(database.reminders).get();
    expect(rows, hasLength(2));
    final restored = rows.singleWhere((r) => r.entityId == task.id);
    expect(restored.triggerAt, task.dueAt);
    expect(jsonDecode(restored.metadata)['other'], 'keep');
    expect(jsonDecode(restored.metadata)['snoozed'], isNot(true));
    expect(pending, hasLength(2));
  });

  test('a platform scheduling failure does not discard healthy reminders',
      () async {
    final failed = await seedTask();
    final healthy = await seedTask(title: 'Healthy');
    onSchedule = (args) async {
      if ((args['payload'] as String).contains(failed.id)) {
        pending.remove(args['id']);
        throw PlatformException(code: 'ALARM_FAILED');
      }
    };
    await service.rebuildFuture(database);
    expect(
        pending.values
            .any((args) => (args['payload'] as String).contains(healthy.id)),
        isTrue);
    expect(await database.select(database.reminders).get(), hasLength(2));
  });

  test('a partial habit log does not suppress the target reminder', () async {
    final habit = await HabitRepository(database).create(const HabitDraft(
      name: 'Two glasses',
      targetCount: 2,
      reminderPolicy: '23:59',
    ));
    final day = DateTime.now().add(const Duration(days: 1));
    await HabitRepository(database).checkIn(habit.id, day, value: 1);
    await service.rebuildFuture(database);
    final rows = await database.select(database.reminders).get();
    expect(
        rows.where((row) =>
            row.entityId == habit.id &&
            DateKeys.toLocalDateKey(
                    DateTime.fromMillisecondsSinceEpoch(row.triggerAt)) ==
                DateKeys.toLocalDateKey(day)),
        hasLength(1));
    await HabitRepository(database).checkIn(habit.id, day, value: 2);
    await service.rebuildFuture(database);
    final completeRows = await database.select(database.reminders).get();
    expect(
        completeRows.where((row) =>
            row.entityId == habit.id &&
            DateKeys.toLocalDateKey(
                    DateTime.fromMillisecondsSinceEpoch(row.triggerAt)) ==
                DateKeys.toLocalDateKey(day)),
        isEmpty);
  });

  for (final snooze in [false, true]) {
    test(
        'rebuild preserves a concurrent ${snooze ? "snooze" : "disable"} and native state',
        () async {
      final task = await seedTask();
      final reminder = await seedReminder(task);
      final moved =
          DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
      var changed = false;
      onSchedule = (_) async {
        if (changed) return;
        changed = true;
        // Simulate another isolate writing while a native call is in flight.
        await (database.update(database.reminders)
              ..where((row) => row.id.equals(reminder.id)))
            .write(RemindersCompanion(
          enabled: Value(snooze),
          triggerAt: Value(snooze ? moved : reminder.triggerAt),
          metadata: Value(snooze ? '{"snoozed":true}' : '{}'),
          version: Value(reminder.version + 1),
        ));
      };
      await service.rebuildFuture(database);
      final actual = await database.select(database.reminders).getSingle();
      expect(actual.version, reminder.version + 1);
      expect(actual.enabled, snooze);
      expect(actual.triggerAt, snooze ? moved : reminder.triggerAt);
      if (!snooze) {
        expect(pending, isEmpty);
      } else {
        final scheduled = DateTime.parse(
            pending[reminder.notificationId]!['scheduledDateTime'] as String);
        final shanghaiClock =
            DateTime.fromMillisecondsSinceEpoch(moved, isUtc: true)
                .add(const Duration(hours: 8));
        expect((scheduled.hour, scheduled.minute),
            (shanghaiClock.hour, shanghaiClock.minute));
      }
    });
  }

  test('a reminder center edit made during rebuild is applied afterward',
      () async {
    final task = await seedTask();
    final reminder = await seedReminder(task);
    final entered = Completer<void>();
    final release = Completer<void>();
    onSchedule = (_) async {
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final rebuild = service.rebuildFuture(database);
    await entered.future;
    final edit = ReminderRepository(database, notifications: service)
        .setEnabled(reminder.id, false);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait([rebuild, edit]);
    expect((await database.select(database.reminders).getSingle()).enabled,
        isFalse);
    expect(pending, isEmpty);
  });

  test(
      'malformed medication configuration does not stop other reminder sources',
      () async {
    await database
        .into(database.medicationPlans)
        .insert(MedicationPlansCompanion.insert(
          name: 'Invalid',
          startDate: DateKeys.toLocalDateKey(DateTime.now()),
          reminderTimesJson: const Value('{}'),
        ));
    final task = await seedTask();
    await service.rebuildFuture(database);
    expect(
        (await database.select(database.reminders).get())
            .any((r) => r.entityId == task.id),
        isTrue);
  });

  test(
      'task completion from notification schedules the next recurring occurrence',
      () async {
    final task = await TaskRepository(database).create(TaskDraft(
      title: 'Daily',
      dueAt: DateTime.now().add(const Duration(days: 1)),
      repeatRule: 'FREQ=DAILY',
    ));
    await service.rebuildFuture(database);
    final reply = Completer<void>();
    messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(
          'didReceiveNotificationResponse',
          {
            'notificationResponseType': 1,
            'actionId': 'TASK_DONE',
            'payload': 'TASK:${task.id}'
          },
        )),
        (_) => reply.complete());
    await reply.future;
    var scheduled = false;
    for (var attempt = 0; attempt < 100; attempt++) {
      final tasks = await database.select(database.tasks).get();
      final next = tasks.where((r) => r.id != task.id).firstOrNull;
      if (next != null &&
          pending.values
              .any((args) => (args['payload'] as String).contains(next.id))) {
        scheduled = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(scheduled, isTrue);
    expect(
        pending.values
            .any((args) => (args['payload'] as String).contains(task.id)),
        isFalse);
  });

  test('notification callbacks cannot bypass an ongoing rebuild', () async {
    final task = await seedTask();
    await service.rebuildFuture(database);
    final entered = Completer<void>();
    final release = Completer<void>();
    onSchedule = (_) async {
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final rebuild = service.rebuildFuture(database);
    await entered.future;
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(
          'didReceiveNotificationResponse',
          {
            'notificationResponseType': 1,
            'actionId': 'TASK_DONE',
            'payload': 'TASK:${task.id}'
          },
        )),
        (_) => reply.complete());
    await reply.future;
    await Future<void>.delayed(Duration.zero);
    final statusDuringRebuild =
        (await TaskRepository(database).get(task.id)).status;
    release.complete();
    await rebuild;
    for (var attempt = 0; attempt < 100; attempt++) {
      if ((await TaskRepository(database).get(task.id)).status ==
              TaskStatus.done &&
          pending.isEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(statusDuringRebuild, TaskStatus.todo);
    expect(
        (await TaskRepository(database).get(task.id)).status, TaskStatus.done);
    expect(pending, isEmpty);
  });

  test('planning never resurrects reminders removed by another isolate',
      () async {
    await database.close();
    final interceptor = _DuringPlanning();
    database = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(interceptor));
    final task = await seedTask();
    final reminder = await seedReminder(task);
    var changed = false;
    interceptor.action = () async {
      changed = true;
      await TaskRepository(database).setStatus(task.id, TaskStatus.done);
      await (database.delete(database.reminders)
            ..where((row) => row.id.equals(reminder.id)))
          .go();
    };
    await service.rebuildFuture(database);
    expect(changed, isTrue);
    expect(await database.select(database.reminders).get(), isEmpty);
    expect(pending, isEmpty);
  });

  test(
      'reminder replenishment is registered even when automatic backups are disabled',
      () async {
    final previous = WorkmanagerPlatform.instance;
    final fake = _Workmanager();
    WorkmanagerPlatform.instance = fake;
    addTearDown(() => WorkmanagerPlatform.instance = previous);
    await BackgroundBackupScheduler.sync(BackupFrequency.disabled);
    expect(fake.tasks.keys, contains('lifehub.periodicReminderRefresh'));
    expect(fake.tasks['lifehub.periodicReminderRefresh']!.inDays, lessThan(14));
    expect(fake.tasks.keys,
        isNot(contains(BackgroundBackupScheduler.backupTaskName)));
    expect(
        fake.tasks.keys,
        containsAll([
          BackgroundBackupScheduler.automationTaskName,
          BackgroundBackupScheduler.widgetTaskName
        ]));
  });
}
