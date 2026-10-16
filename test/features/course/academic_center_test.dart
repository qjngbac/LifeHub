import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/course/data/academic_repository.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/course/presentation/academic_center_page.dart';
import 'package:lifehub/features/course/presentation/courses_page.dart';

void main() {
  late AppDatabase db;
  late CourseRepository courseRepo;
  late AcademicRepository academicRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    courseRepo = CourseRepository(db);
    academicRepo = AcademicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('globalOverview aggregates assignments, exams, materials, and grades across courses', () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
    final semester = await courseRepo.createSemester(SemesterDraft(
      name: '2026年秋季学期',
      start: start,
      end: start.add(const Duration(days: 16 * 7 - 1)),
      totalWeeks: 16,
    ));

    final mathCourse = await courseRepo.createCourse(CourseDraft(
      name: '高等数学',
      semesterId: semester.id,
      color: '#4F46E5',
    ));
    final osCourse = await courseRepo.createCourse(CourseDraft(
      name: '操作系统',
      semesterId: semester.id,
      color: '#22C55E',
    ));

    // 1. Math assignment & exam
    await academicRepo.createAssignment(
      courseId: mathCourse.id,
      title: '高数第4章课后习题',
      dueAt: DateTime.now().add(const Duration(days: 2)),
      submissionMethod: '学习通',
    );
    await academicRepo.createExam(
      courseId: mathCourse.id,
      title: '高数期中考试',
      start: DateTime.now().add(const Duration(days: 10)),
      end: DateTime.now().add(const Duration(days: 10, hours: 2)),
      location: '教三-101',
    );

    // 2. OS material & grade
    await academicRepo.createMaterial(
      courseId: osCourse.id,
      title: '进程调度算法讲义',
      content: 'FCFS, SJF, RR算法核心原理与实现比较',
    );
    await academicRepo.saveGrade(CourseGradeDraft(
      courseId: osCourse.id,
      title: '操作系统实验1',
      score: 95,
      maximum: 100,
    ));

    // 3. Test globalOverview
    final overview = await academicRepo.globalOverview(semesterId: semester.id);
    expect(overview.courses.length, 2);
    expect(overview.assignments.length, 1);
    expect(overview.assignments.first.courseName, '高等数学');
    expect(overview.assignments.first.title, '高数第4章课后习题');
    expect(overview.assignments.first.submitted, isFalse);

    expect(overview.exams.length, 1);
    expect(overview.exams.first.courseName, '高等数学');
    expect(overview.exams.first.title, '高数期中考试');
    expect(overview.exams.first.location, '教三-101');

    expect(overview.materials.length, 1);
    expect(overview.materials.first.courseName, '操作系统');
    expect(overview.materials.first.title, '进程调度算法讲义');

    expect(overview.grades.length, 1);
    expect(overview.grades.first.courseName, '操作系统');
    expect(overview.grades.first.grade.score, 95);

    // 4. Test toggle assignment status
    await academicRepo.toggleAssignmentStatus(overview.assignments.first.taskId);
    final updatedOverview = await academicRepo.globalOverview(semesterId: semester.id);
    expect(updatedOverview.assignments.first.submitted, isTrue);
  });

  testWidgets('CoursesPage top AppBar has Scheme A actions and opens AcademicCenterPage', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
    final semester = await courseRepo.createSemester(SemesterDraft(
      name: '2026年秋季学期',
      start: start,
      end: start.add(const Duration(days: 16 * 7 - 1)),
      totalWeeks: 16,
    ));
    await courseRepo.savePeriods(semester.id, const [
      CoursePeriod(startMinutes: 480, endMinutes: 530),
    ]);
    final course = await courseRepo.createCourse(CourseDraft(
      name: '离散数学',
      semesterId: semester.id,
      color: '#3B82F6',
    ));
    await courseRepo.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: DateTime.monday,
      startMinutes: 480,
      endMinutes: 530,
      weekSet: '1-16',
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CoursesPage()),
    ));
    await tester.pumpAndSettle();

    // Verify Scheme A components in AppBar:
    // 1. School icon for Academic Center
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    expect(find.byTooltip('学业中心'), findsOneWidget);
    // 2. Edit TextButton
    expect(find.text('编辑'), findsOneWidget);
    // 3. Overflow menu button
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // Verify opening more menu reveals Settings and Desktop shortcut
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('课程表设置'), findsOneWidget);
    expect(find.text('添加到手机桌面'), findsOneWidget);

    // Close menu by tapping barrier
    await tester.tapAt(const Offset(50, 50));
    await tester.pumpAndSettle();

    // Tap Academic Center button to navigate to AcademicCenterPage
    await tester.tap(find.byTooltip('学业中心'));
    await tester.pumpAndSettle();

    expect(find.byType(AcademicCenterPage), findsOneWidget);
    expect(find.text('学业中心'), findsOneWidget);
    expect(find.text('作业'), findsOneWidget);
    expect(find.text('考试'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('成绩'), findsOneWidget);
    expect(find.text('全部课程 (1)'), findsOneWidget);
    expect(find.text('离散数学'), findsWidgets);
  });
}
