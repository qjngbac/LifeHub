import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/course/data/course_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/today/application/today_service.dart';

void main() {
  test('today aggregates due tasks, events and scheduled habits', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final day = DateTime(2026, 8, 8);
    await TaskRepository(database).create(TaskDraft(
      title: '今日任务',
      dueAt: DateTime(2026, 8, 8, 18),
    ));
    await EventRepository(database).create(EventDraft(
      title: '今日会议',
      start: DateTime(2026, 8, 8, 10),
      end: DateTime(2026, 8, 8, 11),
    ));
    await HabitRepository(database).create(const HabitDraft(name: '喝水'));

    final snapshot = await TodayService(database).load(day);
    expect(snapshot.tasks.single.title, '今日任务');
    expect(snapshot.events.single.title, '今日会议');
    expect(snapshot.habits.single.habit.name, '喝水');
    expect(snapshot.habits.single.completed, isFalse);
  });

  test('today timed tasks are ordered by end time descending', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    await repository.create(TaskDraft(
      title: 'earlier',
      startAt: DateTime(2026, 8, 8, 8),
      dueAt: DateTime(2026, 8, 8, 9),
    ));
    await repository.create(TaskDraft(
      title: 'later',
      startAt: DateTime(2026, 8, 8, 19),
      dueAt: DateTime(2026, 8, 8, 21),
    ));

    final snapshot = await TodayService(database).load(DateTime(2026, 8, 8));
    expect(snapshot.tasks.map((task) => task.title), ['later', 'earlier']);
  });

  test('today events exclude projected courses', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final courses = CourseRepository(database);
    final semester = await courses.createSemester(SemesterDraft(
      name: '秋季学期',
      start: DateTime(2026, 8, 10),
      end: DateTime(2026, 12, 20),
      totalWeeks: 19,
    ));
    final course = await courses.createCourse(CourseDraft(
      name: '离散数学',
      semesterId: semester.id,
    ));
    await courses.createSchedule(CourseScheduleDraft(
      courseId: course.id,
      weekday: DateTime.monday,
      startMinutes: 610,
      endMinutes: 765,
      weekSet: '1-19',
    ));

    final snapshot = await TodayService(database).load(DateTime(2026, 8, 10));

    expect(snapshot.events, isEmpty);
  });

  test('today includes enabled anniversaries within the next thirty days',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = AnniversaryRepository(database);
    await repository.create(AnniversaryDraft(
      title: '快到的纪念日',
      date: DateTime(2024, 8, 20),
    ));
    await repository.create(AnniversaryDraft(
      title: '很远的纪念日',
      date: DateTime(2024, 12, 20),
    ));
    await repository.create(AnniversaryDraft(
      title: '不显示',
      date: DateTime(2024, 8, 15),
      showInToday: false,
    ));

    final snapshot = await TodayService(database).load(DateTime(2026, 8, 9));
    expect(snapshot.anniversaries.single.entry.title, '快到的纪念日');
    expect(snapshot.anniversaries.single.daysUntil, 11);
  });

  test('today includes current goals and an active focus session', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final goals = GoalRepository(database);
    final goal = await goals.create(const GoalDraft(
      name: '学习目标',
      progressMode: GoalProgressMode.manual,
      manualProgress: .4,
    ));
    await FocusRepository(database).start(
      FocusDraft(plannedMinutes: 25, entityType: 'GOAL', entityId: goal.id),
      now: DateTime.utc(2026, 8, 9, 1),
    );

    final snapshot = await TodayService(database).load(DateTime(2026, 8, 9));

    expect(snapshot.goals.single.goal.name, '学习目标');
    expect(snapshot.goals.single.progress, .4);
    expect(snapshot.focus?.plannedMinutes, 25);
  });
}
