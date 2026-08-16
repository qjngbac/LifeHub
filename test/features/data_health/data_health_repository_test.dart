import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/data_health/data/data_health_repository.dart';

void main() {
  test('reports orphan references and reminders targeting deleted records',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            id: const Value('orphan-task'),
            title: '孤立任务',
            projectId: const Value('missing-project'),
          ),
        );
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            id: const Value('deleted-task'),
            title: '删除任务',
            deletedAt: Value(DateTime.utc(2026, 8, 1).millisecondsSinceEpoch),
          ),
        );
    await database.into(database.reminders).insert(
          RemindersCompanion.insert(
            entityType: 'TASK',
            entityId: 'deleted-task',
            triggerAt: DateTime.utc(2026, 8, 10).millisecondsSinceEpoch,
            notificationId: 99,
          ),
        );

    final report = await DataHealthRepository(database).inspect();

    expect(report.issues.map((issue) => issue.code),
        containsAll(['ORPHAN_TASK_PROJECT', 'REMINDER_DELETED_ENTITY']));
    expect(report.hasErrors, isTrue);
  });

  test('healthy empty database produces no issue', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final report = await DataHealthRepository(database).inspect();
    expect(report.issues, isEmpty);
    expect(report.hasErrors, isFalse);
  });

  test('reports orphan trip, missing attachment file and invalid entity link',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.tripProfiles).insert(
          TripProfilesCompanion.insert(
            id: const Value('orphan-trip'),
            projectId: 'missing-project',
            startDate: 20260812,
            endDate: 20260814,
          ),
        );
    await database.into(database.attachments).insert(
          AttachmentsCompanion.insert(
            id: const Value('missing-file'),
            displayName: 'missing.txt',
            storedPath: 'Z:/definitely-missing/lifehub.txt',
            byteSize: 5,
            contentDigest: '1234',
          ),
        );
    await database.into(database.entityLinks).insert(
          EntityLinksCompanion.insert(
            sourceType: 'GOAL',
            sourceId: 'missing-goal',
            targetType: 'TASK',
            targetId: 'missing-task',
          ),
        );

    final codes = (await DataHealthRepository(database).inspect())
        .issues
        .map((issue) => issue.code)
        .toSet();
    expect(
        codes,
        containsAll({
          'ORPHAN_TRIP_PROJECT',
          'MISSING_ATTACHMENT_FILE',
          'ORPHAN_ENTITY_LINK'
        }));
  });

  test('reports invalid media progress and missing series references',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.mediaEntries).insert(
          MediaEntriesCompanion.insert(
            title: '错误集数',
            category: 'TV',
            entryType: 'SEASON',
            totalEpisodes: const Value(2),
            completedEpisodes: const Value(3),
          ),
        );
    await database.into(database.mediaEntries).insert(
          MediaEntriesCompanion.insert(
            title: '孤立作品',
            category: 'MOVIE',
            entryType: 'MOVIE',
            seriesId: const Value('missing-series'),
          ),
        );

    final codes = (await DataHealthRepository(database).inspect())
        .issues
        .map((issue) => issue.code)
        .toSet();
    expect(
        codes, containsAll({'INVALID_MEDIA_PROGRESS', 'ORPHAN_MEDIA_SERIES'}));
  });

  test('reports invalid and orphan V1.9 daily scenario records', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.courseGrades).insert(
          CourseGradesCompanion.insert(
            courseId: 'missing-course',
            title: '孤立成绩',
            score: 120,
          ),
        );
    await database.into(database.subscriptions).insert(
          SubscriptionsCompanion.insert(
            name: '无效订阅',
            amountMinor: 0,
            cycleUnit: 'MONTH',
            nextRenewalDate: 20260901,
          ),
        );
    await database.into(database.maintenanceLogs).insert(
          MaintenanceLogsCompanion.insert(
            planId: 'missing-plan',
            completedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
          ),
        );
    await database.into(database.readingItems).insert(
          ReadingItemsCompanion.insert(
            title: '错误进度',
            currentProgress: const Value(9),
            totalProgress: const Value(5),
          ),
        );
    await database.into(database.parcels).insert(
          ParcelsCompanion.insert(
            title: '错误日期快递',
            arrivedAt: Value(DateTime(2026, 9, 10).millisecondsSinceEpoch),
            pickupDeadline: Value(DateTime(2026, 9, 9).millisecondsSinceEpoch),
          ),
        );
    await database.into(database.householdItems).insert(
          HouseholdItemsCompanion.insert(
            name: '负库存',
            itemKind: const Value('CONSUMABLE'),
            quantity: const Value(-1),
          ),
        );

    final codes = (await DataHealthRepository(database).inspect())
        .issues
        .map((issue) => issue.code)
        .toSet();
    expect(
      codes,
      containsAll({
        'ORPHAN_COURSE_GRADE',
        'INVALID_COURSE_GRADE',
        'INVALID_SUBSCRIPTION',
        'ORPHAN_MAINTENANCE_LOG',
        'INVALID_READING_PROGRESS',
        'INVALID_PARCEL_RANGE',
        'INVALID_CONSUMABLE_STOCK',
      }),
    );
  });
}
