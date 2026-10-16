import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/course/domain/course_grade_rules.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class CourseGradeDraft {
  const CourseGradeDraft({
    required this.courseId,
    required this.title,
    required this.score,
    this.maximum = 100,
    this.weight,
    this.gradeType = 'OTHER',
    this.occurredDate,
    this.notes,
  });

  final String courseId;
  final String title;
  final double score;
  final double maximum;
  final double? weight;
  final String gradeType;
  final DateTime? occurredDate;
  final String? notes;
}

class AcademicOverview {
  const AcademicOverview({
    required this.openAssignments,
    required this.futureExams,
    required this.materials,
    required this.grades,
  });

  final List<AcademicAssignment> openAssignments;
  final List<AcademicExam> futureExams;
  final List<RelatedEntity> materials;
  final List<CourseGradeEntry> grades;

  int get pendingAssignmentCount =>
      openAssignments.where((item) => !item.submitted).length;
}

class AcademicAssignment {
  const AcademicAssignment({
    required this.entity,
    required this.submitted,
    this.submissionMethod,
    this.dueAt,
  });

  final RelatedEntity entity;
  final String? submissionMethod;
  final DateTime? dueAt;
  final bool submitted;

  String get title => entity.title;

  String? get deadlineLabel {
    final value = dueAt;
    if (value == null) return null;
    return '${value.year}年${value.month}月${value.day}日 '
        '${_timeLabel(value)} 截止';
  }
}

class AcademicExam {
  const AcademicExam({
    required this.entity,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final RelatedEntity entity;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  String get title => entity.title;

  String get scheduleLabel {
    final date = '${start.year}年${start.month}月${start.day}日';
    if (allDay) return date;
    return '$date ${_timeLabel(start)}-${_timeLabel(end)}';
  }
}

class GlobalAcademicOverview {
  const GlobalAcademicOverview({
    required this.courses,
    required this.assignments,
    required this.exams,
    required this.materials,
    required this.grades,
  });

  final List<CourseEntry> courses;
  final List<GlobalAcademicAssignment> assignments;
  final List<GlobalAcademicExam> exams;
  final List<GlobalAcademicMaterial> materials;
  final List<GlobalAcademicGrade> grades;

  int get pendingAssignmentCount =>
      assignments.where((item) => !item.submitted).length;
  int get upcomingExamCount => exams.length;
}

class GlobalAcademicAssignment {
  const GlobalAcademicAssignment({
    required this.courseId,
    required this.courseName,
    required this.courseColor,
    required this.taskId,
    required this.title,
    required this.submitted,
    this.submissionMethod,
    this.dueAt,
  });

  final String courseId;
  final String courseName;
  final String courseColor;
  final String taskId;
  final String title;
  final bool submitted;
  final String? submissionMethod;
  final DateTime? dueAt;

  String? get deadlineLabel {
    final value = dueAt;
    if (value == null) return null;
    return '${value.year}年${value.month}月${value.day}日 '
        '${_timeLabel(value)} 截止';
  }
}

class GlobalAcademicExam {
  const GlobalAcademicExam({
    required this.courseId,
    required this.courseName,
    required this.courseColor,
    required this.eventId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.notes,
  });

  final String courseId;
  final String courseName;
  final String courseColor;
  final String eventId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? notes;

  String get scheduleLabel {
    final date = '${start.year}年${start.month}月${start.day}日';
    if (allDay) return date;
    return '$date ${_timeLabel(start)}-${_timeLabel(end)}';
  }
}

class GlobalAcademicMaterial {
  const GlobalAcademicMaterial({
    required this.courseId,
    required this.courseName,
    required this.courseColor,
    required this.materialId,
    required this.title,
    this.content,
    required this.updatedAt,
  });

  final String courseId;
  final String courseName;
  final String courseColor;
  final String materialId;
  final String title;
  final String? content;
  final int updatedAt;
}

class GlobalAcademicGrade {
  const GlobalAcademicGrade({
    required this.courseId,
    required this.courseName,
    required this.courseColor,
    required this.grade,
  });

  final String courseId;
  final String courseName;
  final String courseColor;
  final CourseGradeEntry grade;
}

class AcademicRepository {
  AcademicRepository(this._database);
  final AppDatabase _database;

  Future<TaskEntry> createAssignment({
    required String courseId,
    required String title,
    DateTime? dueAt,
    String? submissionMethod,
    String? description,
  }) async {
    await _requireCourse(courseId);
    late TaskEntry result;
    await _database.transaction(() async {
      result = await TaskRepository(_database).create(TaskDraft(
        title: title,
        description: _optional(submissionMethod) ?? _optional(description),
        category: TaskCategory.study,
        dueAt: dueAt,
      ));
      await _link(courseId, 'TASK', result.id);
    });
    return result;
  }

  Future<EventEntry> createExam({
    required String courseId,
    required String title,
    required DateTime start,
    required DateTime end,
    String? location,
    String? notes,
    bool allDay = false,
  }) async {
    await _requireCourse(courseId);
    late EventEntry result;
    await _database.transaction(() async {
      result = await EventRepository(_database).create(EventDraft(
        title: title,
        start: start,
        end: end,
        eventType: 'STUDY',
        allDay: allDay,
        localDate: allDay ? DateKeys.toLocalDateKey(start) : null,
        location: location,
        notes: notes,
      ));
      await _link(courseId, 'EVENT', result.id);
    });
    return result;
  }

  Future<SavedItemEntry> createMaterial({
    required String courseId,
    required String title,
    String? content,
  }) async {
    await _requireCourse(courseId);
    late SavedItemEntry result;
    await _database.transaction(() async {
      result = await SavedItemRepository(_database).create(SavedItemDraft(
        title: title,
        content: content,
        itemType: SavedItemType.document,
        associationType: 'COURSE',
        associationId: courseId,
      ));
      await _link(courseId, 'SAVED_ITEM', result.id);
    });
    return result;
  }

  Future<void> linkMaterial(String courseId, String savedItemId) async {
    await _requireCourse(courseId);
    await SavedItemRepository(_database).get(savedItemId);
    await _link(courseId, 'SAVED_ITEM', savedItemId);
  }

  Future<CourseGradeEntry> saveGrade(CourseGradeDraft draft) async {
    await _requireCourse(draft.courseId);
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    CourseGradeRules.validate(
      score: draft.score,
      maximum: draft.maximum,
      weight: draft.weight,
    );
    return _database.into(_database.courseGrades).insertReturning(
          CourseGradesCompanion.insert(
            courseId: draft.courseId,
            title: title,
            gradeType: Value(draft.gradeType),
            score: draft.score,
            maximum: Value(draft.maximum),
            weight: Value(draft.weight),
            occurredDate: Value(draft.occurredDate == null
                ? null
                : DateKeys.toLocalDateKey(draft.occurredDate!)),
            notes: Value(_optional(draft.notes)),
          ),
        );
  }

  Future<List<CourseGradeEntry>> listGrades(String courseId) => (_database
          .select(_database.courseGrades)
        ..where((row) => row.courseId.equals(courseId) & row.deletedAt.isNull())
        ..orderBy([(row) => OrderingTerm.desc(row.occurredDate)]))
      .get();

  Future<void> submitAssignment(String id) async {
    final task = await TaskRepository(_database).get(id);
    if (task.deletedAt != null) throw StateError('Assignment was deleted.');
    if (task.status == TaskStatus.done) return;
    await TaskRepository(_database).setStatus(id, TaskStatus.done);
  }

  Future<void> toggleAssignmentStatus(String id) async {
    final task = await TaskRepository(_database).get(id);
    if (task.deletedAt != null) throw StateError('Assignment was deleted.');
    final nextStatus =
        task.status == TaskStatus.done ? TaskStatus.todo : TaskStatus.done;
    await TaskRepository(_database).setStatus(id, nextStatus);
  }

  Future<void> deleteAssignment(String id) =>
      TaskRepository(_database).delete(id);

  Future<void> deleteExam(String id) => EventRepository(_database).delete(id);

  Future<void> deleteMaterial(String id) =>
      SavedItemRepository(_database).delete(id);

  Future<void> deleteGrade(String id) async {
    final current = await (_database.select(_database.courseGrades)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (current == null) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.courseGrades)
          ..where((row) => row.id.equals(id)))
        .write(CourseGradesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  Future<AcademicOverview> overview(String courseId) async {
    final relations =
        await RelationRepository(_database).relationsFor(EntityReference(
      type: 'COURSE',
      id: courseId,
    ));
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final assignments = <AcademicAssignment>[];
    final exams = <AcademicExam>[];
    final materials = <RelatedEntity>[];
    for (final relation in relations) {
      final ref = relation.entity.reference;
      if (ref.type == 'TASK') {
        final row = await (_database.select(_database.tasks)
              ..where((item) => item.id.equals(ref.id)))
            .getSingleOrNull();
        if (row != null && row.deletedAt == null) {
          assignments.add(AcademicAssignment(
            entity: relation.entity,
            submissionMethod: _optional(row.description),
            submitted: row.status == TaskStatus.done,
            dueAt: row.dueAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    row.dueAt!,
                    isUtc: true,
                  ).toLocal(),
          ));
        }
      } else if (ref.type == 'EVENT') {
        final row = await (_database.select(_database.events)
              ..where((item) => item.id.equals(ref.id)))
            .getSingleOrNull();
        if (row != null && row.startAt >= now && row.deletedAt == null) {
          exams.add(AcademicExam(
            entity: relation.entity,
            start: DateTime.fromMillisecondsSinceEpoch(
              row.startAt,
              isUtc: true,
            ).toLocal(),
            end: DateTime.fromMillisecondsSinceEpoch(
              row.endAt,
              isUtc: true,
            ).toLocal(),
            allDay: row.allDay,
          ));
        }
      } else if (ref.type == 'SAVED_ITEM') {
        materials.add(relation.entity);
      }
    }
    assignments.sort((a, b) {
      if (a.submitted != b.submitted) return a.submitted ? 1 : -1;
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue == null && bDue == null) return a.title.compareTo(b.title);
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return AcademicOverview(
      openAssignments: assignments,
      futureExams: exams,
      materials: materials,
      grades: await listGrades(courseId),
    );
  }

  Future<GlobalAcademicOverview> globalOverview({String? semesterId}) async {
    final coursesQuery = _database.select(_database.courses)
      ..where((row) => row.deletedAt.isNull());
    if (semesterId != null) {
      coursesQuery.where((row) => row.semesterId.equals(semesterId));
    }
    final courses = await coursesQuery.get();
    final courseMap = {for (final c in courses) c.id: c};
    final courseIds = courses.map((c) => c.id).toSet();

    if (courseIds.isEmpty) {
      return const GlobalAcademicOverview(
        courses: [],
        assignments: [],
        exams: [],
        materials: [],
        grades: [],
      );
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final assignments = <GlobalAcademicAssignment>[];
    final exams = <GlobalAcademicExam>[];
    final materials = <GlobalAcademicMaterial>[];
    final seenMaterialIds = <String>{};

    for (final course in courses) {
      final relations =
          await RelationRepository(_database).relationsFor(EntityReference(
        type: 'COURSE',
        id: course.id,
      ));

      for (final relation in relations) {
        final ref = relation.entity.reference;
        if (ref.type == 'TASK') {
          final row = await (_database.select(_database.tasks)
                ..where((item) => item.id.equals(ref.id)))
              .getSingleOrNull();
          if (row != null && row.deletedAt == null) {
            assignments.add(GlobalAcademicAssignment(
              courseId: course.id,
              courseName: course.name,
              courseColor: course.color,
              taskId: row.id,
              title: row.title,
              submissionMethod: _optional(row.description),
              submitted: row.status == TaskStatus.done,
              dueAt: row.dueAt == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      row.dueAt!,
                      isUtc: true,
                    ).toLocal(),
            ));
          }
        } else if (ref.type == 'EVENT') {
          final row = await (_database.select(_database.events)
                ..where((item) => item.id.equals(ref.id)))
              .getSingleOrNull();
          if (row != null && row.startAt >= now && row.deletedAt == null) {
            exams.add(GlobalAcademicExam(
              courseId: course.id,
              courseName: course.name,
              courseColor: course.color,
              eventId: row.id,
              title: row.title,
              start: DateTime.fromMillisecondsSinceEpoch(
                row.startAt,
                isUtc: true,
              ).toLocal(),
              end: DateTime.fromMillisecondsSinceEpoch(
                row.endAt,
                isUtc: true,
              ).toLocal(),
              allDay: row.allDay,
              location: _optional(row.location),
              notes: _optional(row.notes),
            ));
          }
        } else if (ref.type == 'SAVED_ITEM') {
          final item = await (_database.select(_database.savedItems)
                ..where((s) => s.id.equals(ref.id) & s.deletedAt.isNull()))
              .getSingleOrNull();
          if (item != null && !seenMaterialIds.contains(item.id)) {
            seenMaterialIds.add(item.id);
            materials.add(GlobalAcademicMaterial(
              courseId: course.id,
              courseName: course.name,
              courseColor: course.color,
              materialId: item.id,
              title: item.title,
              content: item.content,
              updatedAt: item.updatedAt,
            ));
          }
        }
      }

      final directMaterials = await (_database.select(_database.savedItems)
            ..where((s) =>
                s.associationType.equals('COURSE') &
                s.associationId.equals(course.id) &
                s.deletedAt.isNull()))
          .get();
      for (final item in directMaterials) {
        if (!seenMaterialIds.contains(item.id)) {
          seenMaterialIds.add(item.id);
          materials.add(GlobalAcademicMaterial(
            courseId: course.id,
            courseName: course.name,
            courseColor: course.color,
            materialId: item.id,
            title: item.title,
            content: item.content,
            updatedAt: item.updatedAt,
          ));
        }
      }
    }

    final gradeRows = await (_database.select(_database.courseGrades)
          ..where((row) =>
              row.courseId.isIn(courseIds) & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.occurredDate)]))
        .get();

    final grades = gradeRows.map((row) {
      final course = courseMap[row.courseId];
      return GlobalAcademicGrade(
        courseId: row.courseId,
        courseName: course?.name ?? '未知课程',
        courseColor: course?.color ?? '#4F46E5',
        grade: row,
      );
    }).toList();

    assignments.sort((a, b) {
      if (a.submitted != b.submitted) return a.submitted ? 1 : -1;
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue == null && bDue == null) return a.title.compareTo(b.title);
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });

    exams.sort((a, b) => a.start.compareTo(b.start));
    materials.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return GlobalAcademicOverview(
      courses: courses,
      assignments: assignments,
      exams: exams,
      materials: materials,
      grades: grades,
    );
  }

  Future<void> _requireCourse(String id) async {
    final row = await (_database.select(_database.courses)
          ..where((item) => item.id.equals(id) & item.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) throw StateError('Course not found: $id');
  }

  Future<void> _link(String courseId, String type, String id) =>
      RelationRepository(_database).link(
        EntityReference(type: 'COURSE', id: courseId),
        EntityReference(type: type, id: id),
        relationType: 'ACADEMIC',
      );
}

String _timeLabel(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
