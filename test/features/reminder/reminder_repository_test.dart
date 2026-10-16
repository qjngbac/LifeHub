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

  test(
    'supported reminder entities have titles and labels while matches stay hidden',
    () async {
      const types = [
        'TASK',
        'EVENT',
        'COURSE',
        'COURSE_SCHEDULE',
        'HABIT',
        'ANNIVERSARY',
        'MEDICATION',
        'CREDENTIAL',
        'SUBSCRIPTION',
        'HOUSEHOLD',
        'MAINTENANCE',
        'PARCEL',
        'MATCH',
      ];
      final now = DateTime.now().toUtc();
      await database
          .into(database.tasks)
          .insert(
            TasksCompanion.insert(id: const Value('TASK'), title: 'TASK title'),
          );
      await database
          .into(database.events)
          .insert(
            EventsCompanion.insert(
              id: const Value('EVENT'),
              title: 'EVENT title',
              startAt: now.millisecondsSinceEpoch,
              endAt: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
            ),
          );
      await database
          .into(database.semesters)
          .insert(
            SemestersCompanion.insert(
              id: const Value('semester'),
              name: 'semester',
              startDate: 20261001,
              endDate: 20261201,
            ),
          );
      await database
          .into(database.courses)
          .insert(
            CoursesCompanion.insert(
              id: const Value('COURSE'),
              name: 'COURSE title',
              semesterId: 'semester',
            ),
          );
      await database
          .into(database.courseSchedules)
          .insert(
            CourseSchedulesCompanion.insert(
              id: const Value('COURSE_SCHEDULE'),
              courseId: 'COURSE',
              weekday: 1,
              startMinutes: 600,
              endMinutes: 660,
            ),
          );
      await database
          .into(database.habits)
          .insert(
            HabitsCompanion.insert(
              id: const Value('HABIT'),
              name: 'HABIT title',
            ),
          );
      await database
          .into(database.anniversaries)
          .insert(
            AnniversariesCompanion.insert(
              id: const Value('ANNIVERSARY'),
              title: 'ANNIVERSARY title',
              date: 20261001,
            ),
          );
      await database
          .into(database.medicationPlans)
          .insert(
            MedicationPlansCompanion.insert(
              id: const Value('MEDICATION'),
              name: 'MEDICATION title',
              startDate: 20261001,
            ),
          );
      await database
          .into(database.credentialRecords)
          .insert(
            CredentialRecordsCompanion.insert(
              id: const Value('CREDENTIAL'),
              name: 'CREDENTIAL title',
            ),
          );
      await database
          .into(database.subscriptions)
          .insert(
            SubscriptionsCompanion.insert(
              id: const Value('SUBSCRIPTION'),
              name: 'SUBSCRIPTION title',
              amountMinor: 100,
              cycleUnit: 'MONTH',
              nextRenewalDate: 20261101,
            ),
          );
      await database
          .into(database.householdItems)
          .insert(
            HouseholdItemsCompanion.insert(
              id: const Value('HOUSEHOLD'),
              name: 'HOUSEHOLD title',
            ),
          );
      await database
          .into(database.maintenancePlans)
          .insert(
            MaintenancePlansCompanion.insert(
              id: const Value('MAINTENANCE'),
              title: 'MAINTENANCE title',
              intervalDays: 30,
              nextDueAt: now
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch,
            ),
          );
      await database
          .into(database.parcels)
          .insert(
            ParcelsCompanion.insert(
              id: const Value('PARCEL'),
              title: 'PARCEL title',
            ),
          );
      await database
          .into(database.matchRecords)
          .insert(
            MatchRecordsCompanion.insert(
              id: const Value('MATCH'),
              sportType: 'football',
              competition: 'hidden',
              participantA: 'A',
              participantB: 'B',
              matchDate: 20261001,
            ),
          );
      for (var index = 0; index < types.length; index++) {
        await database
            .into(database.reminders)
            .insert(
              RemindersCompanion.insert(
                entityType: types[index],
                entityId: types[index],
                notificationId: 700 + index,
                triggerAt: now
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
              ),
            );
      }

      final views = await repository.listWindow(now: now);
      expect(views.map((view) => view.entityType).toSet(), {
        'TASK',
        'EVENT',
        'COURSE',
        'COURSE_SCHEDULE',
        'HABIT',
        'ANNIVERSARY',
        'MEDICATION',
        'CREDENTIAL',
        'SUBSCRIPTION',
        'HOUSEHOLD',
        'MAINTENANCE',
        'PARCEL',
      });
      expect(
        {
          for (final view in views)
            view.entityType: (view.title, view.typeLabel),
        },
        {
          'TASK': ('TASK title', '任务'),
          'EVENT': ('EVENT title', '日程'),
          'COURSE': ('COURSE title', '课程'),
          'COURSE_SCHEDULE': ('COURSE title', '课程'),
          'HABIT': ('HABIT title', '习惯'),
          'ANNIVERSARY': ('ANNIVERSARY title', '纪念日'),
          'MEDICATION': ('MEDICATION title', '用药'),
          'CREDENTIAL': ('CREDENTIAL title', '证件'),
          'SUBSCRIPTION': ('SUBSCRIPTION title', '订阅'),
          'HOUSEHOLD': ('HOUSEHOLD title', '消耗品'),
          'MAINTENANCE': ('MAINTENANCE title', '维护'),
          'PARCEL': ('PARCEL title', '快递'),
        },
      );
    },
  );

  test(
    'medication and credential reminders are visible and can be disabled or snoozed',
    () async {
      final notifications = _FakeNotifications();
      final synced = ReminderRepository(database, notifications: notifications);
      final plan = await database
          .into(database.medicationPlans)
          .insertReturning(
            MedicationPlansCompanion.insert(
              name: 'Daily medicine',
              startDate: 20261001,
            ),
          );
      final credential = await database
          .into(database.credentialRecords)
          .insertReturning(CredentialRecordsCompanion.insert(name: 'Passport'));
      final now = DateTime.now().toUtc();
      for (final (type, entity, id) in [
        ('MEDICATION', plan.id, 601),
        ('CREDENTIAL', credential.id, 602),
      ]) {
        await database
            .into(database.reminders)
            .insert(
              RemindersCompanion.insert(
                id: Value(type),
                entityType: type,
                entityId: entity,
                triggerAt: now
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
                notificationId: id,
              ),
            );
      }
      final visible = await synced.listWindow(now: now);
      expect(
        visible.map((row) => row.title),
        containsAll(['Daily medicine', 'Passport']),
      );
      expect(visible.map((row) => row.typeLabel), containsAll(['用药', '证件']));
      await synced.setEnabled('MEDICATION', false);
      await synced.snooze('CREDENTIAL', now.add(const Duration(hours: 2)));
      expect(notifications.canceled, [601]);
      expect(notifications.scheduled.single.entityId, credential.id);
      expect(
        notifications.scheduled.single.triggerAt,
        now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'future reminders exclude deleted entities and resolve their titles',
    () async {
      final tasks = TaskRepository(database);
      final visible = await tasks.create(const TaskDraft(title: '明天交报告'));
      final deleted = await tasks.create(const TaskDraft(title: '已经删除'));
      await tasks.delete(deleted.id);
      final now = DateTime.utc(2026, 8, 9, 12);

      await database
          .into(database.reminders)
          .insert(
            RemindersCompanion.insert(
              id: const Value('visible'),
              entityType: 'TASK',
              entityId: visible.id,
              triggerAt: now
                  .add(const Duration(hours: 2))
                  .millisecondsSinceEpoch,
              notificationId: 101,
            ),
          );
      await database
          .into(database.reminders)
          .insert(
            RemindersCompanion.insert(
              id: const Value('deleted'),
              entityType: 'TASK',
              entityId: deleted.id,
              triggerAt: now
                  .add(const Duration(hours: 3))
                  .millisecondsSinceEpoch,
              notificationId: 102,
            ),
          );

      final result = await repository.listWindow(now: now);

      expect(result, hasLength(1));
      expect(result.single.title, '明天交报告');
      expect(result.single.pastDue, isFalse);
    },
  );

  test('snooze moves the trigger and disabling hides it by default', () async {
    final task = await TaskRepository(
      database,
    ).create(const TaskDraft(title: '喝水'));
    final now = DateTime.utc(2026, 8, 9, 12);
    await database
        .into(database.reminders)
        .insert(
          RemindersCompanion.insert(
            id: const Value('reminder'),
            entityType: 'TASK',
            entityId: task.id,
            triggerAt: now
                .subtract(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
            notificationId: 103,
          ),
        );

    expect((await repository.listWindow(now: now)).single.pastDue, isTrue);
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

  test(
    'disable and snooze synchronize the Android notification bridge',
    () async {
      final notifications = _FakeNotifications();
      final synced = ReminderRepository(database, notifications: notifications);
      final task = await TaskRepository(
        database,
      ).create(const TaskDraft(title: '同步提醒'));
      final now = DateTime.now().toUtc();
      await database
          .into(database.reminders)
          .insert(
            RemindersCompanion.insert(
              id: const Value('sync-reminder'),
              entityType: 'TASK',
              entityId: task.id,
              triggerAt: now
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
              notificationId: 501,
            ),
          );

      await synced.setEnabled('sync-reminder', false);
      expect(notifications.canceled, [501]);

      final snoozed = now.add(const Duration(hours: 2));
      await synced.snooze('sync-reminder', snoozed);
      expect(notifications.scheduled, hasLength(1));
      expect(
        notifications.scheduled.single.triggerAt,
        snoozed.millisecondsSinceEpoch,
      );
      expect(notifications.scheduled.single.metadata, contains('snoozed'));
    },
  );

  test('match reminders are hidden and cannot be changed by users', () async {
    final match = await database
        .into(database.matchRecords)
        .insertReturning(
          MatchRecordsCompanion.insert(
            sportType: '足球',
            competition: '英超',
            participantA: '阿森纳',
            participantB: '切尔西',
            matchDate: 20260920,
            startAt: Value(
              DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
            ),
            timezoneId: const Value('Asia/Shanghai'),
          ),
        );
    await database
        .into(database.reminders)
        .insert(
          RemindersCompanion.insert(
            id: const Value('match-reminder'),
            entityType: 'MATCH',
            entityId: match.id,
            triggerAt: DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            notificationId: 900,
            reminderKind: const Value('BEFORE_1H'),
          ),
        );
    expect(await repository.listWindow(now: DateTime.now().toUtc()), isEmpty);
    await expectLater(
      repository.setEnabled('match-reminder', false),
      throwsStateError,
    );
    await expectLater(
      repository.snooze('match-reminder', DateTime.now()),
      throwsStateError,
    );
  });
}
