import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/archive/data/archive_repository.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/location/data/location_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';

void main() {
  late AppDatabase database;
  late ArchiveRepository archive;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    archive = ArchiveRepository(database);
  });

  tearDown(() => database.close());

  test('archive combines modules and filters by title', () async {
    final taskRepository = TaskRepository(database);
    final listRepository = ListRepository(database);
    final eventRepository = EventRepository(database);
    final task = await taskRepository.create(const TaskDraft(title: '旅行任务'));
    final list = await listRepository.createList('旅行清单');
    final event = await eventRepository.create(EventDraft(
      title: '普通日程',
      start: DateTime(2026, 8, 9, 9),
      end: DateTime(2026, 8, 9, 10),
    ));
    await taskRepository.archive(task.id);
    await listRepository.archiveList(list.id);
    await eventRepository.archive(event.id);

    expect((await archive.list()).map((item) => item.type).toSet(),
        {'TASK', 'LIST', 'EVENT'});
    expect((await archive.list(query: '旅行')).map((item) => item.title).toSet(),
        {'旅行任务', '旅行清单'});
  });

  test('restore returns an item to its module and delete removes it', () async {
    final habits = HabitRepository(database);
    final lists = ListRepository(database);
    final habit = await habits.create(const HabitDraft(name: '早睡'));
    final list = await lists.createList('旧清单');
    await habits.archive(habit.id);
    await lists.archiveList(list.id);

    await archive.restore(ArchivedItem(
      type: 'HABIT',
      id: habit.id,
      title: '早睡',
      updatedAt: 0,
    ));
    await archive.delete(ArchivedItem(
      type: 'LIST',
      id: list.id,
      title: '旧清单',
      updatedAt: 0,
    ));

    expect((await habits.list()).single.name, '早睡');
    expect(await archive.list(), isEmpty);
  });

  test('legacy archived course schedules are available in the archive',
      () async {
    final courses = CourseRepository(database);
    final semester = await courses.createSemester(SemesterDraft(
      name: '秋季',
      start: DateTime(2026, 8, 31),
      end: DateTime(2026, 12, 20),
      totalWeeks: 16,
    ));
    final course = await courses.createCourse(
      CourseDraft(name: '高等数学', semesterId: semester.id),
    );
    final schedule = await courses.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: 1,
      startMinutes: 480,
      endMinutes: 530,
      weekSet: '1-16',
    ));
    await courses.archiveSchedule(schedule.id);

    final item = (await archive.list()).single;
    expect(item.type, 'COURSE_SCHEDULE');
    expect(item.title, contains('高等数学'));
    await archive.restore(item);
    expect(await courses.schedules(course.id), hasLength(1));
  });

  test('archived relationship can be found restored and deleted', () async {
    final relationships = RelationshipRepository(database);
    final profile = await relationships.create(
      const RelationshipDraft(name: '小岚'),
    );
    await relationships.archive(profile.id);

    final item = (await archive.list(query: '小岚')).single;
    expect(item.type, 'RELATIONSHIP');
    expect(item.typeLabel, '关系档案');

    await archive.restore(item);
    expect((await relationships.list()).single.id, profile.id);

    await relationships.archive(profile.id);
    await archive.delete(item);
    expect(await archive.list(query: '小岚'), isEmpty);
    expect(await relationships.list(includeArchived: true), isEmpty);
  });

  test('recently deleted task can be restored or permanently purged', () async {
    final tasks = TaskRepository(database);
    final task = await tasks.create(const TaskDraft(title: '误删任务'));
    await tasks.delete(task.id);

    final deleted = (await archive.deletedItems()).single;
    expect(deleted.type, 'TASK');
    expect(await archive.list(), isEmpty);

    await archive.restoreDeleted(deleted);
    expect((await tasks.list()).single.title, '误删任务');

    await tasks.delete(task.id);
    await archive.purgeDeleted((await archive.deletedItems()).single);
    expect(await archive.deletedItems(), isEmpty);
    await expectLater(tasks.get(task.id), throwsStateError);
  });

  test('event archive stays separate from recently deleted', () async {
    final events = EventRepository(database);
    final event = await events.create(EventDraft(
      title: '可恢复日程',
      start: DateTime(2026, 8, 9, 9),
      end: DateTime(2026, 8, 9, 10),
    ));
    await events.archive(event.id);
    expect((await archive.list()).single.title, '可恢复日程');
    expect(await archive.deletedItems(), isEmpty);

    await archive.delete((await archive.list()).single);
    expect(await archive.list(), isEmpty);
    expect((await archive.deletedItems()).single.title, '可恢复日程');
  });

  test('V1.3-V1.5 archive combines goals, saved items, locations and trips',
      () async {
    final goal =
        await GoalRepository(database).create(const GoalDraft(name: '归档目标'));
    final saved = await SavedItemRepository(database)
        .create(const SavedItemDraft(title: '归档资料'));
    final location = await LocationRepository(database)
        .create(const LocationDraft(name: '归档地点'));
    final trip = await TripRepository(database).create(TripDraft(
      name: '归档旅行',
      startDate: DateTime(2026, 8, 12),
      endDate: DateTime(2026, 8, 14),
    ));
    await database
        .update(database.goals)
        .write(const GoalsCompanion(status: Value(GoalStatus.archived)));
    await SavedItemRepository(database).archive(saved.id);
    await LocationRepository(database).archive(location.id);
    await TripRepository(database).archive(trip.id);

    expect((await archive.list()).map((item) => item.type).toSet(),
        {'GOAL', 'SAVED_ITEM', 'LOCATION', 'TRIP'});
    for (final item in await archive.list()) {
      await archive.restore(item);
    }
    expect(await archive.list(), isEmpty);
    expect((await GoalRepository(database).list()).single.id, goal.id);
  });

  test('restoring a deleted goal preserves status and restores its links',
      () async {
    final tasks = TaskRepository(database);
    final goals = GoalRepository(database);
    final task = await tasks.create(const TaskDraft(title: '关联任务'));
    final goal = await goals.create(const GoalDraft(
      name: '暂停目标',
      status: GoalStatus.paused,
    ));
    await goals.link(goal.id, 'TASK', task.id);
    await goals.delete(goal.id);

    await archive.restoreDeleted((await archive.deletedItems()).singleWhere(
      (item) => item.type == 'GOAL',
    ));

    expect((await goals.get(goal.id)).status, GoalStatus.paused);
    expect(await goals.links(goal.id), hasLength(1));
  });

  test('permanently purging a list removes child and generic associations',
      () async {
    final lists = ListRepository(database);
    final list = await lists.createList('待清理清单');
    final item = await lists.addItem(list.id, '孤儿项');
    await database.into(database.entityTags).insert(
          EntityTagsCompanion.insert(
            entityType: 'LIST_ITEM',
            entityId: item.id,
            tagId: 'missing-tag-is-cleaned-first',
          ),
        );
    await lists.deleteList(list.id);

    await archive.purgeDeleted((await archive.deletedItems()).singleWhere(
      (entry) => entry.type == 'LIST',
    ));

    expect(await database.select(database.listItems).get(), isEmpty);
    expect(await database.select(database.entityTags).get(), isEmpty);
  });
}
