import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/review/data/review_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  test('weekly summary combines tasks habits and effective focus time',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final tasks = TaskRepository(database);
    final task = await tasks.create(TaskDraft(
      title: '完成作业',
      dueAt: DateTime(2026, 8, 5, 18),
    ));
    await tasks.setStatus(
      task.id,
      TaskStatus.done,
      now: DateTime.utc(2026, 8, 5, 19),
    );
    final habit =
        await HabitRepository(database).create(const HabitDraft(name: '阅读'));
    await HabitRepository(database).checkIn(habit.id, DateTime(2026, 8, 6));
    final focus = FocusRepository(database);
    final session = await focus.start(
      const FocusDraft(plannedMinutes: 30),
      now: DateTime.utc(2026, 8, 7, 10),
    );
    await focus.finish(
      session.id,
      now: DateTime.utc(2026, 8, 7, 10, 30),
    );

    final summary = await ReviewRepository(database).summary(
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 10),
    );

    expect(summary.completedTasks, 1);
    expect(summary.habitCheckIns, 1);
    expect(summary.focusMinutes, 30);
  });

  test('weekly and monthly reflections are saved and listed by period',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ReviewRepository(database);
    const summary = ReviewSummary(
      completedTasks: 2,
      habitCheckIns: 3,
      focusMinutes: 40,
      activeGoals: 1,
      moodDays: 0,
      lifeEvents: 0,
    );
    await repository.save(ReviewDraft(
      periodType: 'WEEK',
      start: DateTime(2026, 8, 3),
      end: DateTime(2026, 8, 10),
      summary: summary,
      wins: '完成了主要任务',
      blockers: '睡眠不足',
      nextPriorities: '提前规划',
    ));
    await repository.save(ReviewDraft(
      periodType: 'MONTH',
      start: DateTime(2026, 8),
      end: DateTime(2026, 9),
      summary: summary,
    ));

    final values = await repository.list();
    expect(values, hasLength(2));
    expect(values.first.periodType, 'WEEK');
    expect(values.first.wins, '完成了主要任务');
    expect(values.first.blockers, '睡眠不足');
    expect(values.last.periodType, 'MONTH');
  });
}
