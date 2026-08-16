import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/widgets');

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('widget snapshot contains useful counts and excludes private mood text',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await TaskRepository(database).create(TaskDraft(
      title: '桌面任务',
      dueAt: DateTime(2026, 8, 9, 18),
    ));
    await MoodRepository(database).save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.happy,
      note: '绝对不能出现在桌面',
    ));
    Map<Object?, Object?>? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sent = Map<Object?, Object?>.from(call.arguments as Map);
      return true;
    });

    final snapshot = await WidgetSnapshotService(database).refresh(
      now: DateTime(2026, 8, 9, 12),
    );

    expect(snapshot['taskCount'], 1);
    expect(snapshot.values.join(' '), isNot(contains('绝对不能')));
    expect(sent?['taskCount'], 1);
  });

  test(
      'course widget snapshot includes today and future courses for native filtering',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = CourseRepository(database);
    final semester = await repository.createSemester(SemesterDraft(
      name: '秋季学期',
      start: DateTime(2026, 8, 10),
      end: DateTime(2026, 12, 20),
      totalWeeks: 19,
    ));
    final course = await repository.createCourse(CourseDraft(
      name: '离散数学',
      semesterId: semester.id,
      teacher: '张老师',
      room: '203',
    ));
    await repository.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: DateTime.monday,
      startMinutes: 610,
      endMinutes: 765,
      weekSet: '1-19',
    ));
    final second = await repository.createCourse(CourseDraft(
      name: '数据库',
      semesterId: semester.id,
      teacher: '李老师',
      room: '305',
    ));
    await repository.createSchedule(CourseScheduleDraft(
      courseId: second.id,
      weekday: DateTime.tuesday,
      startMinutes: 800,
      endMinutes: 850,
      weekSet: '1-19',
    ));

    final snapshot = await WidgetSnapshotService(database).refresh(
      now: DateTime(2026, 8, 10, 8),
      notifyNative: false,
    );

    expect(snapshot['nextCourseTitle'], '离散数学');
    expect(snapshot['nextCourseTeacher'], '张老师');
    expect(snapshot['nextCourseRoom'], '203');
    final entries = snapshot['courseEntriesJson'] as String;
    expect(entries, contains('张老师'));
    expect(entries, contains('李老师'));
  });
}
