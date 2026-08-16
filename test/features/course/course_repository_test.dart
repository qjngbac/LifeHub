import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/course_repository.dart';

void main() {
  late AppDatabase database;
  late CourseRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = CourseRepository(database);
  });
  tearDown(() => database.close());

  test('course schedule projects into the shared calendar window', () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: '2026 秋季',
      start: DateTime(2026, 8, 31),
      end: DateTime(2026, 12, 20),
      totalWeeks: 16,
    ));
    final course = await repository.createCourse(CourseDraft(
      name: '高等数学',
      semesterId: semester.id,
      teacher: '王老师',
      room: 'A101',
    ));
    await repository.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: DateTime.monday,
      startMinutes: 8 * 60,
      endMinutes: 9 * 60 + 40,
      weekSet: '1-16',
    ));

    final events = await repository.projectedEvents(
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 1),
    );
    expect(events, hasLength(1));
    expect(events.single.title, '高等数学');
    expect(events.single.room, 'A101');
  });
  test('schedule supports exclusions reminder updates and archive', () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: 'term',
      start: DateTime(2026, 8, 3),
      end: DateTime(2026, 11, 22),
      totalWeeks: 16,
    ));
    final course = await repository.createCourse(
      CourseDraft(name: 'course', semesterId: semester.id),
    );
    final schedule = await repository.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: 1,
      startMinutes: 480,
      endMinutes: 540,
      weekSet: '1-16',
    ));
    final updated = await repository.updateSchedule(
      schedule.id,
      CourseScheduleDraft(
        courseId: course.id,
        weekday: 3,
        startMinutes: 600,
        endMinutes: 660,
        weekSet: '1-8,10',
        excludedDateKeys: const {20260812},
        reminderMinutes: 30,
      ),
    );
    expect(updated.weekday, 3);
    expect(updated.reminderMinutes, 30);
    await repository.archiveSchedule(schedule.id);
    expect(await repository.schedules(course.id), isEmpty);
  });

  test('semester period settings and course edits persist', () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: '旧学期',
      start: DateTime(2026, 8, 31),
      end: DateTime(2026, 12, 20),
      totalWeeks: 16,
    ));
    await repository.savePeriods(semester.id, const [
      CoursePeriod(startMinutes: 8 * 60 + 30, endMinutes: 9 * 60 + 20),
      CoursePeriod(startMinutes: 9 * 60 + 30, endMinutes: 10 * 60 + 20),
    ]);
    expect(await repository.loadPeriods(semester.id), const [
      CoursePeriod(startMinutes: 510, endMinutes: 560),
      CoursePeriod(startMinutes: 570, endMinutes: 620),
    ]);

    final updatedSemester = await repository.updateSemester(
      semester.id,
      SemesterDraft(
        name: '新学期',
        start: DateTime(2026, 9, 1),
        end: DateTime(2027, 1, 18),
        totalWeeks: 20,
      ),
    );
    final course = await repository.createCourse(
      CourseDraft(name: '旧课程', semesterId: semester.id),
    );
    final updatedCourse = await repository.updateCourse(
      course.id,
      CourseDraft(
        name: '程序设计',
        semesterId: semester.id,
        teacher: '郭老师',
        room: '302',
        color: '#EF4444',
      ),
    );
    expect(updatedSemester.name, '新学期');
    expect(updatedSemester.totalWeeks, 20);
    expect(updatedCourse.name, '程序设计');
    expect(updatedCourse.teacher, '郭老师');
    expect(updatedCourse.room, '302');
  });

  test('deleting a course also hides its schedules', () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: '学期',
      start: DateTime(2026, 8, 31),
      end: DateTime(2026, 12, 20),
      totalWeeks: 16,
    ));
    final course = await repository.createCourse(
      CourseDraft(name: '高数', semesterId: semester.id),
    );
    await repository.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: 1,
      startMinutes: 480,
      endMinutes: 530,
      weekSet: '1-16',
    ));

    await repository.deleteCourse(course.id);

    expect(await repository.courses(semesterId: semester.id), isEmpty);
    expect(await repository.schedules(course.id), isEmpty);
  });

  test('course and its multi-period schedule are saved atomically', () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: '2026 秋季学期',
      start: DateTime(2026, 8, 31),
      end: DateTime(2027, 1, 10),
      totalWeeks: 19,
    ));

    final saved = await repository.saveCourseWithSchedule(
      course: CourseDraft(
        name: '离散数学',
        semesterId: semester.id,
        teacher: '张老师',
        room: '203',
      ),
      schedule: const CourseScheduleDraft(
        courseId: '',
        weekday: DateTime.monday,
        startMinutes: 610,
        endMinutes: 765,
        weekSet: '1,3,5,7,9,11,13,15,17,19',
      ),
    );

    expect(saved.course.name, '离散数学');
    expect(saved.schedule.courseId, saved.course.id);
    expect(saved.schedule.startMinutes, 610);
    expect(saved.schedule.endMinutes, 765);
  });

  test('exact duplicate is rejected without leaving an orphan course',
      () async {
    final semester = await repository.createSemester(SemesterDraft(
      name: '2026 秋季学期',
      start: DateTime(2026, 8, 31),
      end: DateTime(2027, 1, 10),
      totalWeeks: 19,
    ));
    const schedule = CourseScheduleDraft(
      courseId: '',
      weekday: DateTime.monday,
      startMinutes: 610,
      endMinutes: 765,
      weekSet: '1,3,5,7,9,11,13,15,17,19',
    );
    final course = CourseDraft(name: '离散数学', semesterId: semester.id);

    await repository.saveCourseWithSchedule(
      course: course,
      schedule: schedule,
    );
    await expectLater(
      repository.saveCourseWithSchedule(course: course, schedule: schedule),
      throwsStateError,
    );

    expect(await repository.courses(semesterId: semester.id), hasLength(1));
    expect(await repository.schedulesForSemester(semester.id), hasLength(1));
  });
}
