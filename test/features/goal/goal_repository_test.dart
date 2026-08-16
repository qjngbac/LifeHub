import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late GoalRepository goals;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    goals = GoalRepository(database);
  });
  tearDown(() => database.close());

  test('milestone progress and completion are derived from milestones',
      () async {
    final goal = await goals.create(const GoalDraft(
      name: '通过考试',
      progressMode: GoalProgressMode.milestone,
    ));
    final first = await goals.addMilestone(goal.id, '完成第一轮复习');
    await goals.addMilestone(goal.id, '完成模拟考试');

    expect(await goals.progress(goal.id), 0);
    await goals.completeMilestone(first.id, completed: true);
    expect(await goals.progress(goal.id), 0.5);
  });

  test('task links drive progress and deleting goal keeps the task', () async {
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '背单词'));
    final goal = await goals.create(const GoalDraft(
      name: '提升英语',
      progressMode: GoalProgressMode.task,
    ));
    await goals.link(goal.id, 'TASK', task.id);
    await goals.link(goal.id, 'TASK', task.id);
    expect(await goals.progress(goal.id), 0);

    await TaskRepository(database).setStatus(task.id, TaskStatus.done);
    expect(await goals.progress(goal.id), 1);
    await goals.delete(goal.id);

    expect((await TaskRepository(database).list()).single.id, task.id);
    expect(await goals.list(), isEmpty);
  });

  test('manual progress can be updated and linked objects can be unlinked',
      () async {
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '背单词'));
    final manual = await goals.create(const GoalDraft(
      name: '阅读目标',
      progressMode: GoalProgressMode.manual,
    ));
    final linked = await goals.create(const GoalDraft(
      name: '英语目标',
      progressMode: GoalProgressMode.task,
    ));

    await goals.updateManualProgress(manual.id, .65);
    await goals.link(linked.id, 'TASK', task.id);
    await goals.unlink(linked.id, 'TASK', task.id);

    expect(await goals.progress(manual.id), .65);
    expect(await goals.links(linked.id), isEmpty);
  });
}
