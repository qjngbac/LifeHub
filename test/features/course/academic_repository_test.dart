import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';

void main() {
  test('course creates linked assignment exam material and grade', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester'),
          name: '2026 秋季',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await db.into(db.courses).insert(CoursesCompanion.insert(
          id: const Value('course'),
          name: '离散数学',
          semesterId: 'semester',
        ));
    final repository = AcademicRepository(db);

    final assignment = await repository.createAssignment(
      courseId: 'course',
      title: '完成第三章习题',
      dueAt: DateTime(2026, 8, 20, 20),
      submissionMethod: '学习通提交',
    );
    final exam = await repository.createExam(
      courseId: 'course',
      title: '期中考试',
      start: DateTime(2026, 10, 10, 9),
      end: DateTime(2026, 10, 10, 11),
    );
    final material = await repository.createMaterial(
      courseId: 'course',
      title: '第三章课件',
    );
    final grade = await repository.saveGrade(const CourseGradeDraft(
      courseId: 'course',
      title: '第一次作业',
      score: 18,
      maximum: 20,
    ));

    expect(assignment.category, 'STUDY');
    expect(assignment.description, '学习通提交');
    expect(exam.eventType, 'STUDY');
    expect(material.title, '第三章课件');
    expect(grade.score, 18);
    final relations = RelationRepository(db);
    for (final ref in [
      EntityReference(type: 'TASK', id: assignment.id),
      EntityReference(type: 'EVENT', id: exam.id),
      EntityReference(type: 'SAVED_ITEM', id: material.id),
    ]) {
      expect(
        (await relations.relationsFor(ref))
            .any((item) => item.entity.reference.key == 'COURSE:course'),
        isTrue,
      );
    }
  });

  test('academic overview exposes assignment method and formatted exam time',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester'),
          name: '2026 秋季',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await db.into(db.courses).insert(CoursesCompanion.insert(
          id: const Value('course'),
          name: '高等数学',
          semesterId: 'semester',
        ));
    final repository = AcademicRepository(db);
    await repository.createAssignment(
      courseId: 'course',
      title: '高数第一章',
      submissionMethod: '纸质版交给学习委员',
    );
    await repository.createExam(
      courseId: 'course',
      title: '高数考试',
      start: DateTime(2026, 12, 5, 13, 30),
      end: DateTime(2026, 12, 5, 15, 30),
    );

    final overview = await repository.overview('course');
    expect(overview.openAssignments.single.submissionMethod, '纸质版交给学习委员');
    expect(overview.openAssignments.single.submitted, isFalse);
    expect(overview.futureExams.single.scheduleLabel, '2026年12月5日 13:30-15:30');
  });

  test('assignment can be submitted and all academic records can be deleted',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.semesters).insert(SemestersCompanion.insert(
          id: const Value('semester'),
          name: '2026 秋季',
          startDate: 20260817,
          endDate: 20261220,
        ));
    await db.into(db.courses).insert(CoursesCompanion.insert(
          id: const Value('course'),
          name: '数据库',
          semesterId: 'semester',
        ));
    final repository = AcademicRepository(db);
    final due = DateTime(2026, 8, 20, 21, 30);
    final assignment = await repository.createAssignment(
      courseId: 'course',
      title: '实验一',
      submissionMethod: '学习通',
      dueAt: due,
    );
    final exam = await repository.createExam(
      courseId: 'course',
      title: '期末考试',
      start: DateTime(2026, 12, 10, 9),
      end: DateTime(2026, 12, 10, 11),
    );
    final material = await repository.createMaterial(
      courseId: 'course',
      title: '复习资料',
    );
    final grade = await repository.saveGrade(const CourseGradeDraft(
      courseId: 'course',
      title: '实验一',
      score: 95,
    ));

    var overview = await repository.overview('course');
    expect(overview.openAssignments.single.dueAt, due);
    await repository.submitAssignment(assignment.id);
    overview = await repository.overview('course');
    expect(overview.openAssignments.single.submitted, isTrue);
    expect(overview.pendingAssignmentCount, 0);

    await repository.deleteAssignment(assignment.id);
    await repository.deleteExam(exam.id);
    await repository.deleteMaterial(material.id);
    await repository.deleteGrade(grade.id);
    overview = await repository.overview('course');
    expect(overview.openAssignments, isEmpty);
    expect(overview.futureExams, isEmpty);
    expect(overview.materials, isEmpty);
    expect(overview.grades, isEmpty);
  });
}
