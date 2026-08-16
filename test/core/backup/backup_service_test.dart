import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/backup/encrypted_backup_codec.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/cycle_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/location/data/location_repository.dart';
import 'package:lifehub/features/trip/data/trip_expense_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';

void main() {
  test('encrypted backup decrypts before validating and importing', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await TaskRepository(source).create(const TaskDraft(title: '私密任务'));
    final codec = EncryptedBackupCodec(
      memoryKiB: 1024,
      iterations: 1,
      parallelism: 1,
    );
    final encrypted = await BackupService(source).exportEncryptedJson(
      'strong-password',
      codec: codec,
    );
    await BackupService(target).importEncryptedJson(
      encrypted,
      'strong-password',
      codec: codec,
    );
    expect((await TaskRepository(target).list()).single.title, '私密任务');
  });

  test('V1.7 local intelligence tables round trip through JSON backup',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await source.into(source.weatherLocations).insert(
          WeatherLocationsCompanion.insert(
            name: '海淀区',
            latitude: 39.96,
            longitude: 116.30,
            isDefault: const Value(true),
          ),
        );
    await source.into(source.eveningPrepItems).insert(
          EveningPrepItemsCompanion.insert(title: '充电宝', localDate: 20260812),
        );
    await source.into(source.householdItems).insert(
          HouseholdItemsCompanion.insert(name: '耳机'),
        );
    await source.into(source.medicationPlans).insert(
          MedicationPlansCompanion.insert(name: '用户记录', startDate: 20260801),
        );
    await source.into(source.financeEntries).insert(
          FinanceEntriesCompanion.insert(
            direction: 'EXPENSE',
            amountMinor: 1234,
            occurredAt: DateTime(2026, 8, 11).millisecondsSinceEpoch,
          ),
        );
    await source.into(source.credentialRecords).insert(
          CredentialRecordsCompanion.insert(name: '护照'),
        );

    await BackupService(target)
        .importJson(await BackupService(source).exportJson());

    expect((await target.select(target.weatherLocations).get()).single.name,
        '海淀区');
    expect((await target.select(target.eveningPrepItems).get()).single.title,
        '充电宝');
    expect(
        (await target.select(target.householdItems).get()).single.name, '耳机');
    expect((await target.select(target.medicationPlans).get()).single.name,
        '用户记录');
    expect(
        (await target.select(target.financeEntries).get()).single.amountMinor,
        1234);
    expect((await target.select(target.credentialRecords).get()).single.name,
        '护照');
  });

  test('V1.8 media series and entries round trip through JSON backup',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await source.into(source.mediaSeries).insert(
          MediaSeriesCompanion.insert(
            id: const Value('media-series'),
            title: '星河系列',
            category: 'ANIME',
          ),
        );
    await source.into(source.mediaEntries).insert(
          MediaEntriesCompanion.insert(
            id: const Value('media-entry'),
            seriesId: const Value('media-series'),
            category: 'ANIME',
            entryType: 'SEASON',
            title: '第一季',
            totalEpisodes: const Value(12),
            completedEpisodes: const Value(4),
          ),
        );

    await BackupService(target)
        .importJson(await BackupService(source).exportJson());

    expect(
        (await target.select(target.mediaSeries).get()).single.title, '星河系列');
    final entry = (await target.select(target.mediaEntries).get()).single;
    expect(entry.title, '第一季');
    expect(entry.completedEpisodes, 4);
  });

  test('V1.9 daily scenario tables round trip through JSON backup', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await source.into(source.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester-v19'),
          name: 'V1.9 学期',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await source.into(source.courses).insert(CoursesCompanion.insert(
          id: const Value('course-v19'),
          name: 'V1.9 课程',
          semesterId: 'semester-v19',
        ));
    await source.into(source.courseGrades).insert(
          CourseGradesCompanion.insert(
            id: const Value('grade-v19'),
            courseId: 'course-v19',
            title: '阶段测验',
            score: 88,
          ),
        );
    await source.into(source.subscriptions).insert(
          SubscriptionsCompanion.insert(
            id: const Value('subscription-v19'),
            name: '云盘订阅',
            amountMinor: 1200,
            cycleUnit: 'MONTH',
            nextRenewalDate: 20260901,
          ),
        );
    await source.into(source.householdItems).insert(
          HouseholdItemsCompanion.insert(
            id: const Value('household-v19'),
            name: '净水器',
          ),
        );
    await source.into(source.maintenancePlans).insert(
          MaintenancePlansCompanion.insert(
            id: const Value('maintenance-v19'),
            householdItemId: const Value('household-v19'),
            title: '更换滤芯',
            intervalDays: 90,
            nextDueAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
          ),
        );
    await source.into(source.maintenanceLogs).insert(
          MaintenanceLogsCompanion.insert(
            id: const Value('maintenance-log-v19'),
            planId: 'maintenance-v19',
            completedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
          ),
        );
    await source.into(source.readingItems).insert(
          ReadingItemsCompanion.insert(
            id: const Value('reading-v19'),
            title: '离线读物',
          ),
        );
    await source.into(source.parcels).insert(
          ParcelsCompanion.insert(
            id: const Value('parcel-v19'),
            title: '私密快递',
            pickupCode: const Value('123456'),
          ),
        );

    await BackupService(target)
        .importJson(await BackupService(source).exportJson());

    expect((await target.select(target.courseGrades).get()).single.score, 88);
    expect(
      (await target.select(target.subscriptions).get()).single.name,
      '云盘订阅',
    );
    expect(
      (await target.select(target.maintenancePlans).get()).single.title,
      '更换滤芯',
    );
    expect(await target.select(target.maintenanceLogs).get(), hasLength(1));
    expect(
      (await target.select(target.readingItems).get()).single.title,
      '离线读物',
    );
    expect(
      (await target.select(target.parcels).get()).single.pickupCode,
      '123456',
    );
  });

  test('JSON backup round trips and invalid import keeps current data',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await TaskRepository(source).create(const TaskDraft(title: '备份任务'));
    final json = await BackupService(source).exportJson();

    await BackupService(target).importJson(json);
    expect((await TaskRepository(target).list()).single.title, '备份任务');

    await expectLater(
      BackupService(target).importJson('{"exportVersion":99}'),
      throwsFormatException,
    );
    expect((await TaskRepository(target).list()).single.title, '备份任务');
  });
  test('semantic validation rejects corrupt backup before replacing data',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await TaskRepository(source).create(const TaskDraft(title: 'source'));
    await TaskRepository(target).create(const TaskDraft(title: 'keep me'));

    final payload = jsonDecode(await BackupService(source).exportJson())
        as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final tasks = data['tasks'] as List<dynamic>;
    (tasks.single as Map<String, dynamic>)['status'] = 'BROKEN';

    await expectLater(
      BackupService(target).importJson(jsonEncode(payload)),
      throwsFormatException,
    );
    expect((await TaskRepository(target).list()).single.title, 'keep me');
  });

  test('schema mismatch and duplicate ids are rejected', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await TaskRepository(database).create(const TaskDraft(title: 'one'));
    final payload = jsonDecode(await BackupService(database).exportJson())
        as Map<String, dynamic>;

    payload['schemaVersion'] = 99;
    await expectLater(
      BackupService(database).importJson(jsonEncode(payload)),
      throwsFormatException,
    );

    payload['schemaVersion'] = database.schemaVersion;
    final data = payload['data'] as Map<String, dynamic>;
    final tasks = data['tasks'] as List<dynamic>;
    tasks.add(Map<String, dynamic>.from(tasks.single as Map));
    await expectLater(
      BackupService(database).importJson(jsonEncode(payload)),
      throwsFormatException,
    );
  });

  test('V1.1 life records round trip through JSON backup', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);

    final relationship = await RelationshipRepository(source).create(
      RelationshipDraft(name: '小岚', startDate: DateTime(2025, 2, 14)),
    );
    await MoodRepository(source).save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.happy,
      relationshipId: relationship.id,
    ));
    await LifeEventRepository(source).create(LifeEventDraft(
      title: '一起散步',
      date: DateTime(2026, 8, 9),
      relationshipId: relationship.id,
    ));
    await CycleRepository(source).create(CycleDraft(
      relationshipId: relationship.id,
      start: DateTime(2026, 8, 3),
      end: DateTime(2026, 8, 7),
    ));
    await AnniversaryRepository(source).create(AnniversaryDraft(
      title: '在一起纪念日',
      date: DateTime(2025, 2, 14),
      relationshipId: relationship.id,
    ));

    await BackupService(target)
        .importJson(await BackupService(source).exportJson());

    final restoredRelationship =
        (await RelationshipRepository(target).list()).single;
    expect(restoredRelationship.name, '小岚');
    expect(
      (await MoodRepository(target).forDate(
        DateTime(2026, 8, 9),
        relationshipId: restoredRelationship.id,
      ))!
          .moodCode,
      MoodCatalog.happy,
    );
    expect(
      (await LifeEventRepository(target).forDate(
        DateTime(2026, 8, 9),
        relationshipId: restoredRelationship.id,
      ))
          .single
          .title,
      '一起散步',
    );
    expect(
      await CycleRepository(target)
          .forMonth(restoredRelationship.id, DateTime(2026, 8)),
      hasLength(1),
    );
    expect(
      (await AnniversaryRepository(target)
              .list(relationshipId: restoredRelationship.id))
          .single
          .title,
      '在一起纪念日',
    );
  });

  test('schema one backup without V1.1 tables imports as empty life records',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await TaskRepository(source).create(const TaskDraft(title: '旧版任务'));
    final payload = jsonDecode(await BackupService(source).exportJson())
        as Map<String, dynamic>;
    payload['schemaVersion'] = 1;
    final data = payload['data'] as Map<String, dynamic>;
    for (final key in const [
      'relationshipProfiles',
      'moodLogs',
      'lifeEvents',
      'cycleRecords',
      'anniversaries',
    ]) {
      data.remove(key);
    }

    await BackupService(target).importJson(jsonEncode(payload));
    expect((await TaskRepository(target).list()).single.title, '旧版任务');
    expect(await RelationshipRepository(target).list(), isEmpty);
  });

  test('imports a real legacy V1 payload with renamed and unversioned fields',
      () async {
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    const createdAt = 1720000000000;
    final payload = {
      'exportVersion': 1,
      'schemaVersion': 1,
      'exportedAt': 1720000000,
      'data': {
        'tasks': [
          {
            'id': 'task-v1',
            'title': '旧版任务',
            'description': null,
            'category': null,
            'status': 'TODO',
            'priority': null,
            'dueAt': null,
            'startAt': null,
            'estimatedMinutes': null,
            'actualMinutes': null,
            'projectId': 'project-v1',
            'parentTaskId': null,
            'repeatRule': null,
            'completedAt': null,
            'sortKey': 0.0,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'projects': [
          {
            'id': 'project-v1',
            'name': '旧版项目',
            'status': 'ACTIVE',
            'color': '#6750A4',
            'startAt': null,
            'dueAt': null,
            'progressMode': 1,
            'manualProgress': 0.5,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'events': [
          {
            'id': 'event-v1',
            'title': '旧版日程',
            'eventType': 'LIFE',
            'startAt': createdAt,
            'endAt': createdAt + 3600000,
            'timezoneId': null,
            'allDay': false,
            'localDate': null,
            'locationId': '图书馆',
            'projectId': null,
            'repeatRule': null,
            'sourceType': null,
            'sourceId': null,
            'notes': null,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'semesters': [
          {
            'id': 'semester-v1',
            'name': '旧学期',
            'startDate': 20260801,
            'endDate': 20261231,
            'totalWeeks': 18,
            'currentWeek': 2,
          }
        ],
        'courses': [
          {
            'id': 'course-v1',
            'name': '数学',
            'teacher': null,
            'room': null,
            'semesterId': 'semester-v1',
            'color': '#6750A4',
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'courseSchedules': [
          {
            'id': 'schedule-v1',
            'courseId': 'course-v1',
            'weekday': 1,
            'startTime': 830,
            'endTime': 1010,
            'weekSet': '1-18',
            'roomOverride': null,
            'reminder': 20,
          }
        ],
        'lists': [
          {
            'id': 'list-v1',
            'name': '旧版清单',
            'listType': 'GENERAL',
            'projectId': null,
            'archived': false,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'listItems': [
          {
            'id': 'item-v1',
            'listId': 'list-v1',
            'text': '牛奶',
            'checked': false,
            'quantity': 2,
            'sortKey': 0.0,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'habits': [
          {
            'id': 'habit-v1',
            'name': '喝水',
            'scheduleRule': 'DAILY',
            'targetCount': 1,
            'unit': '次',
            'reminderPolicy': 0,
            'active': true,
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'version': 1,
            'deletedAt': null,
            'syncState': 0,
            'metadata': null,
          }
        ],
        'habitLogs': [
          {
            'id': 'habit-log-v1',
            'habitId': 'habit-v1',
            'localDate': 20260809,
            'value': 1,
            'status': 'DONE',
          }
        ],
        'tags': [
          {'id': 'tag-v1', 'name': '学习', 'color': '#6750A4'}
        ],
        'entityTags': [
          {'entityType': 'TASK', 'entityId': 'task-v1', 'tagId': 'tag-v1'}
        ],
        'changeLogs': <Object?>[],
      }
    };

    final service = BackupService(target);
    expect(service.inspectJson(jsonEncode(payload)).exportedAt,
        DateTime.fromMillisecondsSinceEpoch(1720000000000, isUtc: true));
    await service.importJson(jsonEncode(payload));

    expect((await target.select(target.projects).get()).single.progressMode,
        'MANUAL');
    expect((await target.select(target.events).get()).single.location, '图书馆');
    expect(
        (await target.select(target.courseSchedules).get()).single.startMinutes,
        8 * 60 + 30);
    expect((await target.select(target.lists).get()).single.title, '旧版清单');
    expect(
        (await target.select(target.listItems).get()).single.textValue, '牛奶');
    expect((await target.select(target.habits).get()).single.reminderPolicy,
        isNull);
    expect(await target.select(target.reminders).get(), isEmpty);
  });

  test('inspection reports metadata and record counts without importing',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await TaskRepository(database).create(const TaskDraft(title: '预检任务'));
    final service = BackupService(database);

    final inspection = service.inspectJson(await service.exportJson());

    expect(inspection.schemaVersion, database.schemaVersion);
    expect(inspection.recordCounts['tasks'], 1);
    expect(inspection.exportedAt, isNotNull);
    expect((await TaskRepository(database).list()).single.title, '预检任务');
  });

  test('merge import keeps target-only records and adds source records',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await TaskRepository(source).create(const TaskDraft(title: '来自备份'));
    await TaskRepository(target).create(const TaskDraft(title: '保留本机'));

    await BackupService(target).importJson(
      await BackupService(source).exportJson(),
      mode: ImportMode.merge,
    );

    expect(
      (await TaskRepository(target).list()).map((task) => task.title).toSet(),
      {'来自备份', '保留本机'},
    );
  });

  test('merge import keeps the record with the newest updatedAt', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    const older = TaskEntry(
      id: 'same-task',
      title: '旧标题',
      category: 'LIFE',
      status: 'TODO',
      priority: 0,
      sortKey: 0,
      createdAt: 1000,
      updatedAt: 2000,
      version: 1,
      syncState: 0,
      metadata: '{}',
    );
    final newer = older.copyWith(title: '新标题', updatedAt: 3000);
    await source.into(source.tasks).insert(older);
    await target.into(target.tasks).insert(newer);

    await BackupService(target).importJson(
      await BackupService(source).exportJson(),
      mode: ImportMode.merge,
    );
    expect((await target.select(target.tasks).get()).single.title, '新标题');

    await source.update(source.tasks).write(
          const TasksCompanion(
            title: Value('最新备份'),
            updatedAt: Value(4000),
          ),
        );
    await BackupService(target).importJson(
      await BackupService(source).exportJson(),
      mode: ImportMode.merge,
    );
    expect((await target.select(target.tasks).get()).single.title, '最新备份');
  });

  test('V1.2-V1.5 records and attachment bytes round trip', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceFiles =
        await Directory.systemTemp.createTemp('lifehub-source-');
    final targetFiles =
        await Directory.systemTemp.createTemp('lifehub-target-');
    addTearDown(source.close);
    addTearDown(target.close);
    addTearDown(() => sourceFiles.delete(recursive: true));
    addTearDown(() => targetFiles.delete(recursive: true));

    final goal =
        await GoalRepository(source).create(const GoalDraft(name: '备份目标'));
    await GoalRepository(source).addMilestone(goal.id, '里程碑');
    await InboxRepository(source).capture('备份收件箱');
    final saved = await SavedItemRepository(source).create(
      const SavedItemDraft(title: '备份资料'),
    );
    await LocationRepository(source).create(
      const LocationDraft(name: '备份地点'),
    );
    final trip = await TripRepository(source).create(TripDraft(
      name: '备份旅行',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));
    await TripExpenseRepository(source).create(TripExpenseDraft(
      tripId: trip.id,
      title: '备份餐费',
      amountCents: 3000,
      expenseDate: DateTime(2026, 8, 12),
    ));
    final input = File('${sourceFiles.path}/note.txt');
    await input.writeAsString('attachment body');
    final attachment = await AttachmentRepository(
      source,
      storageRoot: sourceFiles,
    ).importFile(input.path);
    await AttachmentRepository(source, storageRoot: sourceFiles)
        .link(attachment.id, 'SAVED_ITEM', saved.id);

    final sourceChangeLogCount =
        (await source.select(source.changeLogs).get()).length;
    final json = await BackupService(source).exportJson();
    await BackupService(target, attachmentStorageRoot: targetFiles)
        .importJson(json);

    expect(await target.select(target.goals).get(), hasLength(1));
    expect(await target.select(target.milestones).get(), hasLength(1));
    expect(await target.select(target.inboxItems).get(), hasLength(1));
    expect(await target.select(target.savedItems).get(), hasLength(1));
    expect(await target.select(target.locations).get(), hasLength(1));
    expect(await target.select(target.tripProfiles).get(), hasLength(1));
    expect(await target.select(target.tripExpenses).get(), hasLength(1));
    expect(await target.select(target.changeLogs).get(),
        hasLength(sourceChangeLogCount));
    final restored = (await target.select(target.attachments).get()).single;
    expect(await File(restored.storedPath).readAsString(), 'attachment body');
  });

  test('attachment payload must match the declared size and digest', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final files = await Directory.systemTemp.createTemp('lifehub-digest-');
    addTearDown(database.close);
    addTearDown(() => files.delete(recursive: true));
    final input = File('${files.path}/note.txt');
    await input.writeAsString('original bytes');
    await AttachmentRepository(database, storageRoot: files)
        .importFile(input.path);
    final service = BackupService(database);
    final payload =
        jsonDecode(await service.exportJson()) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    final attachments = data['attachmentFiles'] as List<dynamic>;
    (attachments.single as Map<String, dynamic>)['contentBase64'] =
        base64Encode(utf8.encode('tampered bytes'));

    expect(service.importJson(jsonEncode(payload)), throwsFormatException);
  });

  test('replace import removes physical attachment files absent from backup',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    final files = await Directory.systemTemp.createTemp('lifehub-replace-');
    addTearDown(source.close);
    addTearDown(target.close);
    addTearDown(() => files.delete(recursive: true));
    final input = File('${files.path}/old.txt');
    await input.writeAsString('old private attachment');
    final old = await AttachmentRepository(target, storageRoot: files)
        .importFile(input.path);
    expect(await File(old.storedPath).exists(), isTrue);

    await BackupService(target, attachmentStorageRoot: files)
        .importJson(await BackupService(source).exportJson());

    expect(await File(old.storedPath).exists(), isFalse);
    expect(await target.select(target.attachments).get(), isEmpty);
  });
}
