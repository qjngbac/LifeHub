import 'package:lifehub/core/time/date_keys.dart';

class CourseSpec {
  const CourseSpec({
    required this.id,
    required this.name,
    this.teacher,
    this.room,
  });

  final String id;
  final String name;
  final String? teacher;
  final String? room;
}

class SemesterSpec {
  const SemesterSpec({
    required this.id,
    required this.start,
    required this.end,
    required this.totalWeeks,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final int totalWeeks;
}

class CourseScheduleSpec {
  const CourseScheduleSpec({
    required this.id,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.weekSet,
    this.excludedDateKeys = const {},
    this.roomOverride,
    this.reminderMinutes,
  });

  final String id;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final String weekSet;
  final Set<int> excludedDateKeys;
  final String? roomOverride;
  final int? reminderMinutes;
}

class ProjectedCourseEvent {
  const ProjectedCourseEvent({
    required this.stableId,
    required this.courseId,
    required this.title,
    required this.start,
    required this.end,
    this.teacher,
    this.room,
    this.reminderMinutes,
  });

  final String stableId;
  final String courseId;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? teacher;
  final String? room;
  final int? reminderMinutes;
}

abstract final class CourseProjection {
  static List<ProjectedCourseEvent> eventsForWindow({
    required CourseSpec course,
    required SemesterSpec semester,
    required CourseScheduleSpec schedule,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    if (schedule.weekday < DateTime.monday ||
        schedule.weekday > DateTime.sunday) {
      throw ArgumentError.value(schedule.weekday, 'weekday');
    }
    if (schedule.startMinutes < 0 ||
        schedule.endMinutes > 24 * 60 ||
        schedule.endMinutes <= schedule.startMinutes) {
      throw ArgumentError('Invalid course time range.');
    }
    final validWeeks = DateKeys.parseWeekSet(
      schedule.weekSet,
      totalWeeks: semester.totalWeeks,
    );
    var date = DateTime(windowStart.year, windowStart.month, windowStart.day);
    final semesterStart = DateTime(
      semester.start.year,
      semester.start.month,
      semester.start.day,
    );
    if (date.isBefore(semesterStart)) {
      date = semesterStart;
    }
    final semesterEnd = DateTime(
      semester.end.year,
      semester.end.month,
      semester.end.day,
    );
    final result = <ProjectedCourseEvent>[];
    while (date.isBefore(windowEnd) && !date.isAfter(semesterEnd)) {
      final week = DateKeys.semesterWeek(date, semesterStart, semesterEnd);
      final dateKey = DateKeys.toLocalDateKey(date);
      if (date.weekday == schedule.weekday &&
          week != null &&
          validWeeks.contains(week) &&
          !schedule.excludedDateKeys.contains(dateKey)) {
        final start = DateTime(
          date.year,
          date.month,
          date.day,
          schedule.startMinutes ~/ 60,
          schedule.startMinutes % 60,
        );
        final end = DateTime(
          date.year,
          date.month,
          date.day,
          schedule.endMinutes ~/ 60,
          schedule.endMinutes % 60,
        );
        result.add(
          ProjectedCourseEvent(
            stableId: '${schedule.id}:$dateKey',
            courseId: course.id,
            title: course.name,
            start: start,
            end: end,
            teacher: course.teacher,
            room: schedule.roomOverride ?? course.room,
            reminderMinutes: schedule.reminderMinutes,
          ),
        );
      }
      date = date.add(const Duration(days: 1));
    }
    return result;
  }
}
