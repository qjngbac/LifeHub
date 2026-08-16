import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/search/data/search_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/location/data/location_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';
import 'package:lifehub/features/household/data/household_repository.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';
import 'package:lifehub/features/finance/data/subscription_repository.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';
import 'package:lifehub/features/credentials/data/credential_repository.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('global search excludes entertainment content', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final results = await SearchRepository(database).search('迟到理由');

    expect(results, isEmpty);
  });

  test('global search excludes media progress records', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MediaRepository(database).createEntry(const MediaEntryDraft(
      title: '只在影视里搜索的雪山电影',
      category: MediaCategory.movie,
      entryType: MediaEntryType.movie,
    ));

    expect(await SearchRepository(database).search('雪山电影'), isEmpty);
    expect((await MediaRepository(database).search('雪山电影')).length, 1);
  });

  test('search exposes useful V1.7 names but not credential secrets', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await HouseholdRepository(database)
        .create(const HouseholdDraft(name: '露营冰箱'));
    await MedicationRepository(database).createPlan(MedicationPlanDraft(
      name: '露营药物提醒',
      startDate: DateTime(2026, 8, 1),
    ));
    await FinanceRepository(database).create(FinanceDraft(
      direction: FinanceDirection.expense,
      amountMinor: 1000,
      occurredAt: DateTime(2026, 8, 1),
      note: '露营门票',
    ));
    await CredentialRepository(database).create(const CredentialDraft(
      name: '露营证件',
      numberHint: '秘密尾号 7788',
    ));

    final results = await SearchRepository(database).search('露营');
    expect(results.map((value) => value.type).toSet(),
        {'HOUSEHOLD', 'MEDICATION', 'FINANCE'});
    expect(await SearchRepository(database).search('7788'), isEmpty);
  });

  test('search spans task event project list and habit', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await TaskRepository(database).create(const TaskDraft(title: '晨间阅读'));
    await EventRepository(database).create(EventDraft(
      title: '阅读分享会',
      start: DateTime(2026, 8, 8, 10),
      end: DateTime(2026, 8, 8, 11),
    ));
    await ProjectRepository(database).create(const ProjectDraft(name: '阅读计划'));
    await ListRepository(database).createList('阅读书单');
    await HabitRepository(database).create(const HabitDraft(name: '阅读'));

    final results = await SearchRepository(database).search('阅读');
    expect(results.map((value) => value.type).toSet(),
        {'TASK', 'EVENT', 'PROJECT', 'LIST', 'HABIT'});
  });

  test('active search excludes archived and deleted records', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final tasks = TaskRepository(database);
    final lists = ListRepository(database);
    final habits = HabitRepository(database);
    final archivedTask = await tasks.create(const TaskDraft(title: '隐藏归档任务'));
    final deletedTask = await tasks.create(const TaskDraft(title: '隐藏删除任务'));
    final archivedList = await lists.createList('隐藏归档清单');
    final archivedHabit = await habits.create(const HabitDraft(name: '隐藏归档习惯'));
    await tasks.archive(archivedTask.id);
    await tasks.delete(deletedTask.id);
    await lists.archiveList(archivedList.id);
    await habits.archive(archivedHabit.id);

    expect(await SearchRepository(database).search('隐藏'), isEmpty);
  });

  test('search includes V1.1 named records but not private mood notes',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final relationship = await RelationshipRepository(database).create(
      const RelationshipDraft(name: '阅读搭子'),
    );
    await LifeEventRepository(database).create(LifeEventDraft(
      title: '阅读约会',
      date: DateTime(2026, 8, 9),
      relationshipId: relationship.id,
    ));
    await AnniversaryRepository(database).create(AnniversaryDraft(
      title: '阅读日',
      date: DateTime(2025, 8, 9),
    ));
    await MoodRepository(database).save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.happy,
      note: '阅读心得是私密内容',
    ));

    final reading = await SearchRepository(database).search('阅读');
    expect(reading.map((value) => value.type).toSet(),
        {'RELATIONSHIP', 'LIFE_EVENT', 'ANNIVERSARY'});
    expect(await SearchRepository(database).search('私密内容'), isEmpty);
  });

  test('search includes goal, library, location and project-backed trip',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await GoalRepository(database).create(const GoalDraft(name: '西湖目标'));
    await SavedItemRepository(database)
        .create(const SavedItemDraft(title: '西湖攻略'));
    await LocationRepository(database)
        .create(const LocationDraft(name: '西湖断桥'));
    await TripRepository(database).create(TripDraft(
      name: '西湖旅行',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));

    final results = await SearchRepository(database).search('西湖');
    expect(results.map((value) => value.type).toSet(),
        {'GOAL', 'SAVED_ITEM', 'LOCATION', 'TRIP'});
  });

  test('global search does not expose sensitive saved items', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await SavedItemRepository(database).create(const SavedItemDraft(
      title: '私密资料标题',
      content: '只有我能看的正文',
      sensitive: true,
    ));

    expect(await SearchRepository(database).search('私密资料'), isEmpty);
    expect(await SearchRepository(database).search('只有我能看'), isEmpty);
  });

  test('global search includes subscriptions but excludes reading and parcels',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await SubscriptionRepository(database).create(SubscriptionDraft(
      name: '星河云盘订阅',
      amountMinor: 1200,
      cycleUnit: SubscriptionCycleUnit.month,
      nextRenewalDate: DateTime(2026, 9, 1),
    ));
    await ReadingRepository(database).create(
      const ReadingDraft(title: '星河阅读私藏'),
    );
    await ParcelRepository(database).create(
      const ParcelDraft(
        title: '星河快递',
        trackingNumber: 'STAR-7788',
        pickupCode: '998877',
      ),
    );

    final results = await SearchRepository(database).search('星河');
    expect(results.map((value) => value.type).toSet(), {'SUBSCRIPTION'});
    expect(await SearchRepository(database).search('STAR-7788'), isEmpty);
    expect(await SearchRepository(database).search('998877'), isEmpty);
  });
}
