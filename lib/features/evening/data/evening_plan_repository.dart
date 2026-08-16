import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';

class PlannedCourse {
  const PlannedCourse({required this.course, required this.schedule});

  final CourseEntry course;
  final CourseScheduleEntry schedule;
}

class EveningPlan {
  const EveningPlan({
    required this.date,
    required this.tasks,
    required this.events,
    required this.courses,
    required this.prepItems,
  });

  final DateTime date;
  final List<TaskEntry> tasks;
  final List<EventEntry> events;
  final List<PlannedCourse> courses;
  final List<EveningPrepItemEntry> prepItems;
}

class EveningPlanRepository {
  EveningPlanRepository(this._database);

  final AppDatabase _database;

  Future<EveningPlan> load(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final start = day.millisecondsSinceEpoch;
    final end = day.add(const Duration(days: 1)).millisecondsSinceEpoch;
    final dateKey = DateKeys.toLocalDateKey(day);
    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('DONE').not() &
              row.status.equals('CANCELED').not() &
              row.dueAt.isBiggerOrEqualValue(start) &
              row.dueAt.isSmallerThanValue(end))
          ..orderBy([(row) => OrderingTerm(expression: row.dueAt)]))
        .get();
    final events = await (_database.select(_database.events)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.archived.equals(false) &
              row.startAt.isSmallerThanValue(end) &
              row.endAt.isBiggerThanValue(start) &
              (row.sourceType.isNull() | row.sourceType.equals('COURSE').not()))
          ..orderBy([(row) => OrderingTerm(expression: row.startAt)]))
        .get();
    final prepItems = await (_database.select(_database.eveningPrepItems)
          ..where(
              (row) => row.deletedAt.isNull() & row.localDate.equals(dateKey))
          ..orderBy([(row) => OrderingTerm(expression: row.sortKey)]))
        .get();

    final courses = <PlannedCourse>[];
    final semesters = await (_database.select(_database.semesters)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.startDate.isSmallerOrEqualValue(dateKey) &
              row.endDate.isBiggerOrEqualValue(dateKey)))
        .get();
    for (final semester in semesters) {
      final week = DateKeys.semesterWeek(
        day,
        DateKeys.fromLocalDateKey(semester.startDate),
        DateKeys.fromLocalDateKey(semester.endDate),
      );
      if (week == null || week > semester.totalWeeks) continue;
      final semesterCourses = await (_database.select(_database.courses)
            ..where((row) =>
                row.deletedAt.isNull() & row.semesterId.equals(semester.id)))
          .get();
      for (final course in semesterCourses) {
        final schedules = await (_database.select(_database.courseSchedules)
              ..where((row) =>
                  row.deletedAt.isNull() &
                  row.archived.equals(false) &
                  row.courseId.equals(course.id) &
                  row.weekday.equals(day.weekday))
              ..orderBy([
                (row) => OrderingTerm(expression: row.startMinutes),
              ]))
            .get();
        for (final schedule in schedules) {
          final activeWeeks = DateKeys.parseWeekSet(
            schedule.weekSet,
            totalWeeks: semester.totalWeeks,
          );
          final excluded = (jsonDecode(schedule.excludedDates) as List<dynamic>)
              .map((value) => (value as num).toInt())
              .toSet();
          if (activeWeeks.contains(week) && !excluded.contains(dateKey)) {
            courses.add(PlannedCourse(course: course, schedule: schedule));
          }
        }
      }
    }
    courses.sort(
      (a, b) => a.schedule.startMinutes.compareTo(b.schedule.startMinutes),
    );
    return EveningPlan(
      date: day,
      tasks: tasks,
      events: events,
      courses: courses,
      prepItems: prepItems,
    );
  }

  Future<EveningPrepItemEntry> addPrepItem(
    DateTime date,
    String title, {
    String? sourceType,
    String? sourceId,
  }) async {
    final value = title.trim();
    if (value.isEmpty) throw ArgumentError.value(title, 'title');
    return _database.into(_database.eveningPrepItems).insertReturning(
          EveningPrepItemsCompanion.insert(
            title: value,
            localDate: DateKeys.toLocalDateKey(date),
            sourceType: Value(sourceType?.toUpperCase()),
            sourceId: Value(sourceId),
            sortKey: Value(DateTime.now().millisecondsSinceEpoch.toDouble()),
          ),
        );
  }

  Future<void> setPrepChecked(String id, bool checked) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.eveningPrepItems)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(EveningPrepItemsCompanion(
      checked: Value(checked),
      updatedAt: Value(now),
    ));
  }

  Future<void> deletePrepItem(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.eveningPrepItems)
          ..where((row) => row.id.equals(id)))
        .write(EveningPrepItemsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }
}
