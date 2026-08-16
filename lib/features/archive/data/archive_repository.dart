import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/location/data/location_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';

class ArchivedItem {
  const ArchivedItem({
    required this.type,
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String type;
  final String id;
  final String title;
  final int updatedAt;

  String get typeLabel => switch (type) {
        'TASK' => '任务',
        'EVENT' => '日程',
        'PROJECT' => '项目',
        'LIST' => '清单',
        'HABIT' => '习惯',
        'COURSE_SCHEDULE' => '课程时间',
        'COURSE' => '课程',
        'RELATIONSHIP' => '关系档案',
        'ANNIVERSARY' => '纪念日',
        'GOAL' => '目标',
        'SAVED_ITEM' => '资料',
        'LOCATION' => '地点',
        'TRIP' => '旅行',
        _ => type,
      };
}

class ArchiveRepository {
  ArchiveRepository(this._database);

  final AppDatabase _database;

  Future<List<ArchivedItem>> list({String query = ''}) async {
    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() & row.status.equals(TaskStatus.archived)))
        .get();
    final events = await (_database.select(_database.events)
          ..where(
            (row) => row.deletedAt.isNull() & row.archived.equals(true),
          ))
        .get();
    final projects = await (_database.select(_database.projects)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED')))
        .get();
    final lists = await (_database.select(_database.lists)
          ..where((row) => row.deletedAt.isNull() & row.archived.equals(true)))
        .get();
    final habits = await (_database.select(_database.habits)
          ..where((row) => row.deletedAt.isNull() & row.active.equals(false)))
        .get();
    final archivedSchedules = await (_database.select(_database.courseSchedules)
          ..where(
            (row) => row.deletedAt.isNull() & row.archived.equals(true),
          ))
        .get();
    final relationships = await (_database
            .select(_database.relationshipProfiles)
          ..where((row) => row.deletedAt.isNull() & row.active.equals(false)))
        .get();
    final goals = await (_database.select(_database.goals)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED')))
        .get();
    final savedItems = await (_database.select(_database.savedItems)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED')))
        .get();
    final locations = await (_database.select(_database.locations)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED')))
        .get();
    final trips = await (_database.select(_database.tripProfiles)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED')))
        .get();
    final tripProjects = await (_database.select(_database.projects)
          ..where((row) => row.id.isIn(trips.map((value) => value.projectId))))
        .get();
    final tripNames = {
      for (final project in tripProjects) project.id: project.name
    };
    final activeCourses = await (_database.select(_database.courses)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final coursesById = {
      for (final course in activeCourses) course.id: course,
    };
    final items = <ArchivedItem>[
      ...tasks.map((row) => ArchivedItem(
          type: 'TASK',
          id: row.id,
          title: row.title,
          updatedAt: row.updatedAt)),
      ...events.map((row) => ArchivedItem(
          type: 'EVENT',
          id: row.id,
          title: row.title,
          updatedAt: row.updatedAt)),
      ...projects.map((row) => ArchivedItem(
          type: 'PROJECT',
          id: row.id,
          title: row.name,
          updatedAt: row.updatedAt)),
      ...lists.map((row) => ArchivedItem(
          type: 'LIST',
          id: row.id,
          title: row.title,
          updatedAt: row.updatedAt)),
      ...habits.map((row) => ArchivedItem(
          type: 'HABIT',
          id: row.id,
          title: row.name,
          updatedAt: row.updatedAt)),
      ...relationships.map((row) => ArchivedItem(
          type: 'RELATIONSHIP',
          id: row.id,
          title: row.name,
          updatedAt: row.updatedAt)),
      ...goals.map((row) => ArchivedItem(
          type: 'GOAL', id: row.id, title: row.name, updatedAt: row.updatedAt)),
      ...savedItems.map((row) => ArchivedItem(
          type: 'SAVED_ITEM',
          id: row.id,
          title: row.title,
          updatedAt: row.updatedAt)),
      ...locations.map((row) => ArchivedItem(
          type: 'LOCATION',
          id: row.id,
          title: row.name,
          updatedAt: row.updatedAt)),
      ...trips.map((row) => ArchivedItem(
          type: 'TRIP',
          id: row.id,
          title: tripNames[row.projectId] ?? '旅行',
          updatedAt: row.updatedAt)),
      ...archivedSchedules
          .where((row) => coursesById.containsKey(row.courseId))
          .map(
            (row) => ArchivedItem(
              type: 'COURSE_SCHEDULE',
              id: row.id,
              title:
                  '${coursesById[row.courseId]!.name} · 周${row.weekday} ${_minutes(row.startMinutes)}',
              updatedAt: row.updatedAt,
            ),
          ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return items;
    return items
        .where((item) =>
            item.title.toLowerCase().contains(term) ||
            item.typeLabel.contains(term))
        .toList();
  }

  Future<void> restore(ArchivedItem item) async {
    switch (item.type) {
      case 'TASK':
        await TaskRepository(_database).restore(item.id);
      case 'EVENT':
        await EventRepository(_database).restore(item.id);
      case 'LIST':
        await ListRepository(_database).restoreList(item.id);
      case 'HABIT':
        await HabitRepository(_database).restore(item.id);
      case 'PROJECT':
        await _restoreProject(item.id);
      case 'COURSE_SCHEDULE':
        await _restoreCourseSchedule(item.id);
      case 'RELATIONSHIP':
        await RelationshipRepository(_database).restore(item.id);
      case 'GOAL':
        await _setGoalStatus(item.id, 'ACTIVE');
      case 'SAVED_ITEM':
        await SavedItemRepository(_database).restore(item.id);
      case 'LOCATION':
        await LocationRepository(_database).restore(item.id);
      case 'TRIP':
        await TripRepository(_database).restore(item.id);
      default:
        throw ArgumentError.value(item.type, 'type');
    }
  }

  Future<void> delete(ArchivedItem item) async {
    switch (item.type) {
      case 'TASK':
        await TaskRepository(_database).delete(item.id);
      case 'EVENT':
        await EventRepository(_database).delete(item.id);
      case 'LIST':
        await ListRepository(_database).deleteList(item.id);
      case 'HABIT':
        await HabitRepository(_database).delete(item.id);
      case 'PROJECT':
        await _deleteProject(item.id);
      case 'COURSE_SCHEDULE':
        await _deleteCourseSchedule(item.id);
      case 'RELATIONSHIP':
        await RelationshipRepository(_database).delete(item.id);
      case 'GOAL':
        await _deleteGoal(item.id);
      case 'SAVED_ITEM':
        await SavedItemRepository(_database).delete(item.id);
      case 'LOCATION':
        await LocationRepository(_database).delete(item.id);
      case 'TRIP':
        await TripRepository(_database).delete(item.id);
      default:
        throw ArgumentError.value(item.type, 'type');
    }
  }

  Future<void> _restoreProject(String id) async {
    final project = await (_database.select(_database.projects)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.projects)
          ..where((row) => row.id.equals(id)))
        .write(ProjectsCompanion(
      status: const Value('ACTIVE'),
      updatedAt: Value(now),
      version: Value(project.version + 1),
    ));
  }

  Future<void> _setGoalStatus(String id, String status) async {
    final goal = await (_database.select(_database.goals)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.goals)..where((row) => row.id.equals(id)))
        .write(GoalsCompanion(
      status: Value(status),
      updatedAt: Value(now),
      version: Value(goal.version + 1),
    ));
  }

  Future<void> _deleteGoal(String id) async {
    final goal = await (_database.select(_database.goals)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.goals)..where((row) => row.id.equals(id)))
        .write(GoalsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(goal.version + 1),
    ));
  }

  Future<void> _deleteProject(String id) async {
    final project = await (_database.select(_database.projects)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.projects)
          ..where((row) => row.id.equals(id)))
        .write(ProjectsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(project.version + 1),
    ));
  }

  Future<void> _restoreCourseSchedule(String id) async {
    final schedule = await (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .write(CourseSchedulesCompanion(
      deletedAt: const Value(null),
      archived: const Value(false),
      updatedAt: Value(now),
      version: Value(schedule.version + 1),
    ));
  }

  Future<void> _deleteCourseSchedule(String id) async {
    final schedule = await (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingle();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .write(CourseSchedulesCompanion(
      archived: const Value(false),
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(schedule.version + 1),
    ));
  }

  Future<List<ArchivedItem>> deletedItems({String query = ''}) async {
    final tasks = await (_database.select(_database.tasks)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final events = await (_database.select(_database.events)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final projects = await (_database.select(_database.projects)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final lists = await (_database.select(_database.lists)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final habits = await (_database.select(_database.habits)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final courses = await (_database.select(_database.courses)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final schedules = await (_database.select(_database.courseSchedules)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final relationships =
        await (_database.select(_database.relationshipProfiles)
              ..where((row) => row.deletedAt.isNotNull()))
            .get();
    final anniversaries = await (_database.select(_database.anniversaries)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final goals = await (_database.select(_database.goals)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final savedItems = await (_database.select(_database.savedItems)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final locations = await (_database.select(_database.locations)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final trips = await (_database.select(_database.tripProfiles)
          ..where((row) => row.deletedAt.isNotNull()))
        .get();
    final tripProjects = await _database.select(_database.projects).get();
    final tripNames = {
      for (final project in tripProjects) project.id: project.name
    };
    final allCourses = await _database.select(_database.courses).get();
    final courseNames = {
      for (final course in allCourses) course.id: course.name
    };
    final items = <ArchivedItem>[
      ...tasks.map((row) => ArchivedItem(
          type: 'TASK',
          id: row.id,
          title: row.title,
          updatedAt: row.deletedAt!)),
      ...events.map((row) => ArchivedItem(
          type: 'EVENT',
          id: row.id,
          title: row.title,
          updatedAt: row.deletedAt!)),
      ...projects.map((row) => ArchivedItem(
          type: 'PROJECT',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...lists.map((row) => ArchivedItem(
          type: 'LIST',
          id: row.id,
          title: row.title,
          updatedAt: row.deletedAt!)),
      ...habits.map((row) => ArchivedItem(
          type: 'HABIT',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...courses.map((row) => ArchivedItem(
          type: 'COURSE',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...schedules.map((row) => ArchivedItem(
          type: 'COURSE_SCHEDULE',
          id: row.id,
          title: courseNames[row.courseId] ?? '课程时间',
          updatedAt: row.deletedAt!)),
      ...relationships.map((row) => ArchivedItem(
          type: 'RELATIONSHIP',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...anniversaries.map((row) => ArchivedItem(
          type: 'ANNIVERSARY',
          id: row.id,
          title: row.title,
          updatedAt: row.deletedAt!)),
      ...goals.map((row) => ArchivedItem(
          type: 'GOAL',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...savedItems.map((row) => ArchivedItem(
          type: 'SAVED_ITEM',
          id: row.id,
          title: row.title,
          updatedAt: row.deletedAt!)),
      ...locations.map((row) => ArchivedItem(
          type: 'LOCATION',
          id: row.id,
          title: row.name,
          updatedAt: row.deletedAt!)),
      ...trips.map((row) => ArchivedItem(
          type: 'TRIP',
          id: row.id,
          title: tripNames[row.projectId] ?? '旅行',
          updatedAt: row.deletedAt!)),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return items;
    return items
        .where((item) =>
            item.title.toLowerCase().contains(term) ||
            item.typeLabel.contains(term))
        .toList();
  }

  Future<void> restoreDeleted(ArchivedItem item) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    switch (item.type) {
      case 'TASK':
        await (_database.update(_database.tasks)
              ..where((row) => row.id.equals(item.id)))
            .write(TasksCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'EVENT':
        await (_database.update(_database.events)
              ..where((row) => row.id.equals(item.id)))
            .write(EventsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'PROJECT':
        await (_database.update(_database.projects)
              ..where((row) => row.id.equals(item.id)))
            .write(ProjectsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'LIST':
        await (_database.update(_database.lists)
              ..where((row) => row.id.equals(item.id)))
            .write(ListsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'HABIT':
        await (_database.update(_database.habits)
              ..where((row) => row.id.equals(item.id)))
            .write(HabitsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'COURSE':
        await (_database.update(_database.courses)
              ..where((row) => row.id.equals(item.id)))
            .write(CoursesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'COURSE_SCHEDULE':
        await (_database.update(_database.courseSchedules)
              ..where((row) => row.id.equals(item.id)))
            .write(CourseSchedulesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'RELATIONSHIP':
        await (_database.update(_database.relationshipProfiles)
              ..where((row) => row.id.equals(item.id)))
            .write(RelationshipProfilesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'ANNIVERSARY':
        await (_database.update(_database.anniversaries)
              ..where((row) => row.id.equals(item.id)))
            .write(AnniversariesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'GOAL':
        await _database.transaction(() async {
          await (_database.update(_database.goals)
                ..where((row) => row.id.equals(item.id)))
              .write(GoalsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ));
          await (_database.update(_database.entityLinks)
                ..where((row) =>
                    row.sourceType.equals('GOAL') &
                    row.sourceId.equals(item.id) &
                    row.deletedAt.equals(item.updatedAt)))
              .write(EntityLinksCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ));
        });
      case 'SAVED_ITEM':
        await (_database.update(_database.savedItems)
              ..where((row) => row.id.equals(item.id)))
            .write(SavedItemsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'LOCATION':
        await (_database.update(_database.locations)
              ..where((row) => row.id.equals(item.id)))
            .write(LocationsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      case 'TRIP':
        await (_database.update(_database.tripProfiles)
              ..where((row) => row.id.equals(item.id)))
            .write(TripProfilesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ));
      default:
        throw ArgumentError.value(item.type, 'type');
    }
  }

  Future<void> purgeDeleted(ArchivedItem item) async {
    await _database.transaction(() async {
      switch (item.type) {
        case 'TASK':
          await (_database.update(_database.tasks)
                ..where((row) => row.parentTaskId.equals(item.id)))
              .write(const TasksCompanion(parentTaskId: Value(null)));
          await _purgeAssociations('TASK', item.id);
          await (_database.delete(_database.tasks)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'EVENT':
          await _purgeAssociations('EVENT', item.id);
          await (_database.delete(_database.events)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'PROJECT':
          await (_database.update(_database.tasks)
                ..where((row) => row.projectId.equals(item.id)))
              .write(const TasksCompanion(projectId: Value(null)));
          await (_database.update(_database.events)
                ..where((row) => row.projectId.equals(item.id)))
              .write(const EventsCompanion(projectId: Value(null)));
          await (_database.update(_database.lists)
                ..where((row) => row.projectId.equals(item.id)))
              .write(const ListsCompanion(projectId: Value(null)));
          final trips = await (_database.select(_database.tripProfiles)
                ..where((row) => row.projectId.equals(item.id)))
              .get();
          for (final trip in trips) {
            await _purgeTrip(trip.id);
          }
          await _purgeAssociations('PROJECT', item.id);
          await (_database.delete(_database.projects)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'LIST':
          final children = await (_database.select(_database.listItems)
                ..where((row) => row.listId.equals(item.id)))
              .get();
          for (final child in children) {
            await _purgeAssociations('LIST_ITEM', child.id);
          }
          await (_database.delete(_database.listItems)
                ..where((row) => row.listId.equals(item.id)))
              .go();
          await _purgeAssociations('LIST', item.id);
          await (_database.delete(_database.lists)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'HABIT':
          final logs = await (_database.select(_database.habitLogs)
                ..where((row) => row.habitId.equals(item.id)))
              .get();
          for (final log in logs) {
            await _purgeAssociations('HABIT_LOG', log.id);
          }
          await (_database.delete(_database.habitLogs)
                ..where((row) => row.habitId.equals(item.id)))
              .go();
          await _purgeAssociations('HABIT', item.id);
          await (_database.delete(_database.habits)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'COURSE':
          final schedules = await (_database.select(_database.courseSchedules)
                ..where((row) => row.courseId.equals(item.id)))
              .get();
          for (final schedule in schedules) {
            await _purgeAssociations('COURSE_SCHEDULE', schedule.id);
          }
          await (_database.delete(_database.courseSchedules)
                ..where((row) => row.courseId.equals(item.id)))
              .go();
          await _purgeAssociations('COURSE', item.id);
          await (_database.delete(_database.courses)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'COURSE_SCHEDULE':
          await _purgeAssociations('COURSE_SCHEDULE', item.id);
          await (_database.delete(_database.courseSchedules)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'RELATIONSHIP':
          final moods = await (_database.select(_database.moodLogs)
                ..where((row) => row.relationshipId.equals(item.id)))
              .get();
          final events = await (_database.select(_database.lifeEvents)
                ..where((row) => row.relationshipId.equals(item.id)))
              .get();
          final cycles = await (_database.select(_database.cycleRecords)
                ..where((row) => row.relationshipId.equals(item.id)))
              .get();
          final anniversaries = await (_database.select(_database.anniversaries)
                ..where((row) => row.relationshipId.equals(item.id)))
              .get();
          for (final mood in moods) {
            await _purgeAssociations('MOOD', mood.id);
          }
          for (final event in events) {
            await _purgeAssociations('LIFE_EVENT', event.id);
          }
          for (final cycle in cycles) {
            await _purgeAssociations('CYCLE', cycle.id);
          }
          for (final anniversary in anniversaries) {
            await _purgeAssociations('ANNIVERSARY', anniversary.id);
          }
          await (_database.delete(_database.moodLogs)
                ..where((row) => row.relationshipId.equals(item.id)))
              .go();
          await (_database.delete(_database.lifeEvents)
                ..where((row) => row.relationshipId.equals(item.id)))
              .go();
          await (_database.delete(_database.cycleRecords)
                ..where((row) => row.relationshipId.equals(item.id)))
              .go();
          await (_database.delete(_database.anniversaries)
                ..where((row) => row.relationshipId.equals(item.id)))
              .go();
          await _purgeAssociations('RELATIONSHIP', item.id);
          await (_database.delete(_database.relationshipProfiles)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'ANNIVERSARY':
          await _purgeAssociations('ANNIVERSARY', item.id);
          await (_database.delete(_database.anniversaries)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'GOAL':
          final milestones = await (_database.select(_database.milestones)
                ..where((row) => row.goalId.equals(item.id)))
              .get();
          for (final milestone in milestones) {
            await _purgeAssociations('MILESTONE', milestone.id);
          }
          await (_database.delete(_database.milestones)
                ..where((row) => row.goalId.equals(item.id)))
              .go();
          await _purgeAssociations('GOAL', item.id);
          await (_database.delete(_database.goals)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'SAVED_ITEM':
          await _purgeAssociations('SAVED_ITEM', item.id);
          await (_database.delete(_database.savedItems)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'LOCATION':
          await _purgeAssociations('LOCATION', item.id);
          await (_database.delete(_database.locations)
                ..where((row) => row.id.equals(item.id)))
              .go();
        case 'TRIP':
          await _purgeTrip(item.id);
        default:
          throw ArgumentError.value(item.type, 'type');
      }
    });
  }

  Future<void> _purgeTrip(String id) async {
    final expenses = await (_database.select(_database.tripExpenses)
          ..where((row) => row.tripId.equals(id)))
        .get();
    for (final expense in expenses) {
      await _purgeAssociations('TRIP_EXPENSE', expense.id);
    }
    await (_database.delete(_database.tripExpenses)
          ..where((row) => row.tripId.equals(id)))
        .go();
    await _purgeAssociations('TRIP', id);
    await (_database.delete(_database.tripProfiles)
          ..where((row) => row.id.equals(id)))
        .go();
  }

  Future<void> _purgeAssociations(String type, String id) async {
    await (_database.delete(_database.entityTags)
          ..where(
              (row) => row.entityType.equals(type) & row.entityId.equals(id)))
        .go();
    await (_database.delete(_database.reminders)
          ..where(
              (row) => row.entityType.equals(type) & row.entityId.equals(id)))
        .go();
    await (_database.delete(_database.entityLinks)
          ..where((row) =>
              (row.sourceType.equals(type) & row.sourceId.equals(id)) |
              (row.targetType.equals(type) & row.targetId.equals(id))))
        .go();
    await (_database.delete(_database.attachmentLinks)
          ..where(
              (row) => row.entityType.equals(type) & row.entityId.equals(id)))
        .go();
    await (_database.update(_database.focusSessions)
          ..where(
              (row) => row.entityType.equals(type) & row.entityId.equals(id)))
        .write(const FocusSessionsCompanion(
      entityType: Value(null),
      entityId: Value(null),
    ));
    await (_database.update(_database.savedItems)
          ..where((row) =>
              row.associationType.equals(type) & row.associationId.equals(id)))
        .write(const SavedItemsCompanion(
      associationType: Value(null),
      associationId: Value(null),
    ));
  }

  Future<int> purgeExpired({required DateTime before}) async {
    final threshold = before.toUtc().millisecondsSinceEpoch;
    final expired = (await deletedItems())
        .where((item) => item.updatedAt < threshold)
        .toList();
    for (final item in expired) {
      await purgeDeleted(item);
    }
    return expired.length;
  }
}

String _minutes(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
