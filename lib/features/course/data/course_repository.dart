import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/course/domain/course_projection.dart';
import 'package:uuid/uuid.dart';

class SemesterDraft {
  const SemesterDraft({
    required this.name,
    required this.start,
    required this.end,
    required this.totalWeeks,
  });
  final String name;
  final DateTime start;
  final DateTime end;
  final int totalWeeks;
}

class CourseDraft {
  const CourseDraft({
    required this.name,
    required this.semesterId,
    this.teacher,
    this.room,
    this.color = '#4F46E5',
  });
  final String name;
  final String semesterId;
  final String? teacher;
  final String? room;
  final String color;
}

class CourseScheduleDraft {
  const CourseScheduleDraft({
    required this.courseId,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    required this.weekSet,
    this.excludedDateKeys = const {},
    this.roomOverride,
    this.reminderMinutes,
  });
  final String courseId;
  final int weekday;
  final int startMinutes;
  final int endMinutes;
  final String weekSet;
  final Set<int> excludedDateKeys;
  final String? roomOverride;
  final int? reminderMinutes;
}

class CoursePeriod {
  const CoursePeriod({
    required this.startMinutes,
    required this.endMinutes,
  });

  final int startMinutes;
  final int endMinutes;

  Map<String, int> toJson() => {
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  factory CoursePeriod.fromJson(Map<String, dynamic> json) => CoursePeriod(
        startMinutes: json['startMinutes'] as int,
        endMinutes: json['endMinutes'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is CoursePeriod &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);
}

class CourseSaveResult {
  const CourseSaveResult({required this.course, required this.schedule});

  final CourseEntry course;
  final CourseScheduleEntry schedule;
}

class CourseRepository {
  CourseRepository(this._database);
  final AppDatabase _database;

  static const defaultPeriods = <CoursePeriod>[
    CoursePeriod(startMinutes: 8 * 60, endMinutes: 8 * 60 + 50),
    CoursePeriod(startMinutes: 9 * 60, endMinutes: 9 * 60 + 50),
    CoursePeriod(startMinutes: 10 * 60 + 10, endMinutes: 11 * 60),
    CoursePeriod(startMinutes: 11 * 60 + 10, endMinutes: 12 * 60),
    CoursePeriod(startMinutes: 13 * 60 + 30, endMinutes: 14 * 60 + 20),
    CoursePeriod(startMinutes: 14 * 60 + 30, endMinutes: 15 * 60 + 20),
    CoursePeriod(startMinutes: 15 * 60 + 30, endMinutes: 16 * 60 + 20),
    CoursePeriod(startMinutes: 16 * 60 + 30, endMinutes: 17 * 60 + 20),
  ];

  Future<SemesterEntry> createSemester(SemesterDraft draft) async {
    final name = _required(draft.name, 'name');
    if (draft.end.isBefore(draft.start) || draft.totalWeeks < 1) {
      throw ArgumentError('Invalid semester range or week count.');
    }
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.semesters).insert(
            SemestersCompanion.insert(
              id: Value(id),
              name: name,
              startDate: DateKeys.toLocalDateKey(draft.start),
              endDate: DateKeys.toLocalDateKey(draft.end),
              totalWeeks: Value(draft.totalWeeks),
            ),
          );
      await _log('SEMESTER', id);
    });
    return (_database.select(_database.semesters)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<SemesterEntry> updateSemester(String id, SemesterDraft draft) async {
    final current = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Semester not found.');
    final name = _required(draft.name, 'name');
    if (draft.end.isBefore(draft.start) || draft.totalWeeks < 1) {
      throw ArgumentError('Invalid semester range or week count.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.semesters)
          ..where((row) => row.id.equals(id)))
        .write(SemestersCompanion(
      name: Value(name),
      startDate: Value(DateKeys.toLocalDateKey(draft.start)),
      endDate: Value(DateKeys.toLocalDateKey(draft.end)),
      totalWeeks: Value(draft.totalWeeks),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
    await _log('SEMESTER', id, operation: 'UPDATE');
    return (_database.select(_database.semesters)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<CoursePeriod>> loadPeriods(String semesterId) async {
    final key = 'course.periods.$semesterId';
    final row = await (_database.select(_database.moduleConfigs)
          ..where((row) => row.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return defaultPeriods;
    final decoded = jsonDecode(row.value) as List<dynamic>;
    final periods = decoded
        .map((value) =>
            CoursePeriod.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
    _validatePeriods(periods);
    return periods;
  }

  Future<void> savePeriods(
      String semesterId, List<CoursePeriod> periods) async {
    final semester = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(semesterId)))
        .getSingleOrNull();
    if (semester == null) throw StateError('Semester not found.');
    _validatePeriods(periods);
    final key = 'course.periods.$semesterId';
    await _database.into(_database.moduleConfigs).insertOnConflictUpdate(
          ModuleConfigsCompanion.insert(
            key: key,
            value:
                jsonEncode(periods.map((period) => period.toJson()).toList()),
          ),
        );
  }

  Future<CourseSaveResult> saveCourseWithSchedule({
    required CourseDraft course,
    required CourseScheduleDraft schedule,
    String? courseId,
    String? scheduleId,
  }) async {
    final semester = await (_database.select(_database.semesters)
          ..where((row) =>
              row.id.equals(course.semesterId) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (semester == null) throw StateError('Semester not found.');

    final normalizedName = _required(course.name, 'name');
    final normalizedWeeks =
        DateKeys.parseWeekSet(schedule.weekSet, totalWeeks: semester.totalWeeks)
            .toList()
          ..sort();
    final normalizedSchedule = CourseScheduleDraft(
      courseId: courseId ?? '',
      weekday: schedule.weekday,
      startMinutes: schedule.startMinutes,
      endMinutes: schedule.endMinutes,
      weekSet: normalizedWeeks.join(','),
      excludedDateKeys: schedule.excludedDateKeys,
      roomOverride: schedule.roomOverride,
      reminderMinutes: schedule.reminderMinutes,
    );
    _validateSchedule(normalizedSchedule, semester.totalWeeks);

    final savedIds = await _database.transaction(() async {
      final sameNameCourses = await (_database.select(_database.courses)
            ..where((row) =>
                row.semesterId.equals(course.semesterId) &
                row.name.equals(normalizedName) &
                row.deletedAt.isNull()))
          .get();
      final sameNameIds = sameNameCourses.map((value) => value.id).toList();
      if (sameNameIds.isNotEmpty) {
        final candidates = await (_database.select(_database.courseSchedules)
              ..where((row) =>
                  row.courseId.isIn(sameNameIds) &
                  row.weekday.equals(normalizedSchedule.weekday) &
                  row.startMinutes.equals(normalizedSchedule.startMinutes) &
                  row.endMinutes.equals(normalizedSchedule.endMinutes) &
                  row.deletedAt.isNull() &
                  row.archived.equals(false)))
            .get();
        final duplicate = candidates.any((value) {
          if (value.id == scheduleId) return false;
          final weeks = DateKeys.parseWeekSet(
            value.weekSet,
            totalWeeks: semester.totalWeeks,
          );
          return weeks.length == normalizedWeeks.length &&
              weeks.containsAll(normalizedWeeks);
        });
        if (duplicate) throw StateError('相同课程和排课已经存在');
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final resolvedCourseId = courseId ?? const Uuid().v4();
      if (courseId == null) {
        await _database.into(_database.courses).insert(
              CoursesCompanion.insert(
                id: Value(resolvedCourseId),
                name: normalizedName,
                semesterId: course.semesterId,
                teacher: Value(_optional(course.teacher)),
                room: Value(_optional(course.room)),
                color: Value(course.color),
              ),
            );
        await _log('COURSE', resolvedCourseId);
      } else {
        final current = await (_database.select(_database.courses)
              ..where((row) => row.id.equals(resolvedCourseId)))
            .getSingleOrNull();
        if (current == null) throw StateError('Course not found.');
        await (_database.update(_database.courses)
              ..where((row) => row.id.equals(resolvedCourseId)))
            .write(CoursesCompanion(
          name: Value(normalizedName),
          semesterId: Value(course.semesterId),
          teacher: Value(_optional(course.teacher)),
          room: Value(_optional(course.room)),
          color: Value(course.color),
          updatedAt: Value(now),
          version: Value(current.version + 1),
        ));
        await _log('COURSE', resolvedCourseId, operation: 'UPDATE');
      }

      final resolvedScheduleId = scheduleId ?? const Uuid().v4();
      if (scheduleId == null) {
        await _database.into(_database.courseSchedules).insert(
              CourseSchedulesCompanion.insert(
                id: Value(resolvedScheduleId),
                courseId: resolvedCourseId,
                weekday: normalizedSchedule.weekday,
                startMinutes: normalizedSchedule.startMinutes,
                endMinutes: normalizedSchedule.endMinutes,
                weekSet: Value(normalizedSchedule.weekSet),
                excludedDates:
                    Value(jsonEncode(schedule.excludedDateKeys.toList())),
                roomOverride: Value(_optional(schedule.roomOverride)),
                reminderMinutes: Value(schedule.reminderMinutes),
              ),
            );
        await _log('COURSE_SCHEDULE', resolvedScheduleId);
      } else {
        final current = await (_database.select(_database.courseSchedules)
              ..where((row) => row.id.equals(resolvedScheduleId)))
            .getSingleOrNull();
        if (current == null) throw StateError('Schedule not found.');
        await (_database.update(_database.courseSchedules)
              ..where((row) => row.id.equals(resolvedScheduleId)))
            .write(CourseSchedulesCompanion(
          courseId: Value(resolvedCourseId),
          weekday: Value(normalizedSchedule.weekday),
          startMinutes: Value(normalizedSchedule.startMinutes),
          endMinutes: Value(normalizedSchedule.endMinutes),
          weekSet: Value(normalizedSchedule.weekSet),
          excludedDates: Value(jsonEncode(schedule.excludedDateKeys.toList())),
          roomOverride: Value(_optional(schedule.roomOverride)),
          reminderMinutes: Value(schedule.reminderMinutes),
          updatedAt: Value(now),
          version: Value(current.version + 1),
        ));
        await _log('COURSE_SCHEDULE', resolvedScheduleId, operation: 'UPDATE');
      }
      return (resolvedCourseId, resolvedScheduleId);
    });

    final savedCourse = await (_database.select(_database.courses)
          ..where((row) => row.id.equals(savedIds.$1)))
        .getSingle();
    final savedSchedule = await (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(savedIds.$2)))
        .getSingle();
    return CourseSaveResult(course: savedCourse, schedule: savedSchedule);
  }

  Future<CourseEntry> createCourse(CourseDraft draft) async {
    final semester = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(draft.semesterId)))
        .getSingleOrNull();
    if (semester == null) throw StateError('Semester not found.');
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.courses).insert(
            CoursesCompanion.insert(
              id: Value(id),
              name: _required(draft.name, 'name'),
              semesterId: draft.semesterId,
              teacher: Value(_optional(draft.teacher)),
              room: Value(_optional(draft.room)),
              color: Value(draft.color),
            ),
          );
      await _log('COURSE', id);
    });
    return (_database.select(_database.courses)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<CourseEntry> updateCourse(String id, CourseDraft draft) async {
    final current = await (_database.select(_database.courses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Course not found.');
    final semester = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(draft.semesterId)))
        .getSingleOrNull();
    if (semester == null) throw StateError('Semester not found.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.courses)
          ..where((row) => row.id.equals(id)))
        .write(CoursesCompanion(
      name: Value(_required(draft.name, 'name')),
      semesterId: Value(draft.semesterId),
      teacher: Value(_optional(draft.teacher)),
      room: Value(_optional(draft.room)),
      color: Value(draft.color),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
    await _log('COURSE', id, operation: 'UPDATE');
    return (_database.select(_database.courses)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<void> deleteCourse(String id) async {
    final current = await (_database.select(_database.courses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Course not found.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.courseSchedules)
            ..where((row) => row.courseId.equals(id) & row.deletedAt.isNull()))
          .write(CourseSchedulesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await (_database.update(_database.courses)
            ..where((row) => row.id.equals(id)))
          .write(CoursesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('COURSE', id, operation: 'DELETE');
    });
  }

  Future<CourseScheduleEntry> createSchedule(
    CourseScheduleDraft draft,
  ) async {
    final course = await (_database.select(_database.courses)
          ..where((row) => row.id.equals(draft.courseId)))
        .getSingleOrNull();
    if (course == null) throw StateError('Course not found.');
    if (draft.weekday < 1 ||
        draft.weekday > 7 ||
        draft.startMinutes < 0 ||
        draft.endMinutes > 1440 ||
        draft.endMinutes <= draft.startMinutes) {
      throw ArgumentError('Invalid course schedule.');
    }
    final semester = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(course.semesterId)))
        .getSingle();
    _validateSchedule(draft, semester.totalWeeks);
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.courseSchedules).insert(
            CourseSchedulesCompanion.insert(
              id: Value(id),
              courseId: draft.courseId,
              weekday: draft.weekday,
              startMinutes: draft.startMinutes,
              endMinutes: draft.endMinutes,
              weekSet: Value(draft.weekSet),
              excludedDates: Value(jsonEncode(draft.excludedDateKeys.toList())),
              roomOverride: Value(_optional(draft.roomOverride)),
              reminderMinutes: Value(draft.reminderMinutes),
            ),
          );
      await _log('COURSE_SCHEDULE', id);
    });
    return (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<SemesterEntry>> semesters() =>
      (_database.select(_database.semesters)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.startDate)]))
          .get();

  Future<CourseScheduleEntry> updateSchedule(
    String id,
    CourseScheduleDraft draft,
  ) async {
    final current = await (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Schedule not found.');
    final course = await (_database.select(_database.courses)
          ..where((row) => row.id.equals(draft.courseId)))
        .getSingleOrNull();
    if (course == null) throw StateError('Course not found.');
    final semester = await (_database.select(_database.semesters)
          ..where((row) => row.id.equals(course.semesterId)))
        .getSingle();
    _validateSchedule(draft, semester.totalWeeks);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.courseSchedules)
            ..where((row) => row.id.equals(id)))
          .write(CourseSchedulesCompanion(
        courseId: Value(draft.courseId),
        weekday: Value(draft.weekday),
        startMinutes: Value(draft.startMinutes),
        endMinutes: Value(draft.endMinutes),
        weekSet: Value(draft.weekSet),
        excludedDates: Value(jsonEncode(draft.excludedDateKeys.toList())),
        roomOverride: Value(_optional(draft.roomOverride)),
        reminderMinutes: Value(draft.reminderMinutes),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('COURSE_SCHEDULE', id, operation: 'UPDATE');
    });
    return (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<void> archiveSchedule(String id) async {
    final current = await (_database.select(_database.courseSchedules)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Schedule not found.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.courseSchedules)
            ..where((row) => row.id.equals(id)))
          .write(CourseSchedulesCompanion(
        archived: const Value(true),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('COURSE_SCHEDULE', id, operation: 'ARCHIVE');
    });
  }

  Future<List<CourseEntry>> courses({String? semesterId}) {
    final query = _database.select(_database.courses)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (semesterId != null) {
          filter = filter & row.semesterId.equals(semesterId);
        }
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.name)]);
    return query.get();
  }

  Future<List<CourseScheduleEntry>> schedules(String courseId) =>
      (_database.select(_database.courseSchedules)
            ..where((row) =>
                row.courseId.equals(courseId) &
                row.deletedAt.isNull() &
                row.archived.equals(false)))
          .get();

  Future<List<CourseScheduleEntry>> schedulesForSemester(
      String semesterId) async {
    final semesterCourses = await courses(semesterId: semesterId);
    final ids = semesterCourses.map((course) => course.id).toList();
    if (ids.isEmpty) return const [];
    return (_database.select(_database.courseSchedules)
          ..where(
            (row) =>
                row.courseId.isIn(ids) &
                row.deletedAt.isNull() &
                row.archived.equals(false),
          )
          ..orderBy([
            (row) => OrderingTerm(expression: row.startMinutes),
            (row) => OrderingTerm(expression: row.weekday),
          ]))
        .get();
  }

  Future<List<ProjectedCourseEvent>> projectedEvents(
    DateTime start,
    DateTime end,
  ) async {
    if (!end.isAfter(start)) throw ArgumentError('Invalid window.');
    final allSemesters = await semesters();
    final allCourses = await courses();
    final schedules = await (_database.select(_database.courseSchedules)
          ..where(
            (row) => row.deletedAt.isNull() & row.archived.equals(false),
          ))
        .get();
    final semestersById = {for (final value in allSemesters) value.id: value};
    final coursesById = {for (final value in allCourses) value.id: value};
    final result = <ProjectedCourseEvent>[];
    for (final schedule in schedules) {
      final course = coursesById[schedule.courseId];
      final semester = course == null ? null : semestersById[course.semesterId];
      if (course == null || semester == null) continue;
      final excluded = (jsonDecode(schedule.excludedDates) as List)
          .map((value) => value as int)
          .toSet();
      result.addAll(CourseProjection.eventsForWindow(
        course: CourseSpec(
          id: course.id,
          name: course.name,
          teacher: course.teacher,
          room: course.room,
        ),
        semester: SemesterSpec(
          id: semester.id,
          start: DateKeys.fromLocalDateKey(semester.startDate),
          end: DateKeys.fromLocalDateKey(semester.endDate),
          totalWeeks: semester.totalWeeks,
        ),
        schedule: CourseScheduleSpec(
          id: schedule.id,
          weekday: schedule.weekday,
          startMinutes: schedule.startMinutes,
          endMinutes: schedule.endMinutes,
          weekSet: schedule.weekSet,
          excludedDateKeys: excluded,
          roomOverride: schedule.roomOverride,
          reminderMinutes: schedule.reminderMinutes,
        ),
        windowStart: start,
        windowEnd: end,
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  Future<void> _log(String type, String id, {String operation = 'CREATE'}) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: type,
              entityId: id,
              operation: operation,
            ),
          );

  static String _required(String source, String name) {
    final value = source.trim();
    if (value.isEmpty) throw ArgumentError.value(source, name);
    return value;
  }

  static String? _optional(String? source) {
    final value = source?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static void _validateSchedule(CourseScheduleDraft draft, int totalWeeks) {
    if (draft.weekday < 1 ||
        draft.weekday > 7 ||
        draft.startMinutes < 0 ||
        draft.endMinutes > 1440 ||
        draft.endMinutes <= draft.startMinutes ||
        (draft.reminderMinutes != null && draft.reminderMinutes! < 0)) {
      throw ArgumentError('Invalid course schedule.');
    }
    DateKeys.parseWeekSet(draft.weekSet, totalWeeks: totalWeeks);
    for (final key in draft.excludedDateKeys) {
      DateKeys.fromLocalDateKey(key);
    }
  }

  static void _validatePeriods(List<CoursePeriod> periods) {
    if (periods.isEmpty || periods.length > 20) {
      throw ArgumentError('Course periods must contain 1 to 20 rows.');
    }
    var previousEnd = -1;
    for (final period in periods) {
      if (period.startMinutes < 0 ||
          period.endMinutes > 1440 ||
          period.endMinutes <= period.startMinutes ||
          period.startMinutes < previousEnd) {
        throw ArgumentError('Invalid or overlapping course periods.');
      }
      previousEnd = period.endMinutes;
    }
  }
}
