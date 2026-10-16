import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(database);
  });

  tearDown(() => database.close());

  test('title-only task is trimmed and persisted with defaults', () async {
    final task = await repository.create(const TaskDraft(title: '  整理桌面  '));

    expect(task.title, '整理桌面');
    expect(task.status, TaskStatus.todo);
    expect(task.category, TaskCategory.life);
    expect(await repository.list(), hasLength(1));
    expect(await database.select(database.changeLogs).get(), hasLength(1));
  });

  test('task status transition persists completion timestamp', () async {
    final task = await repository.create(const TaskDraft(title: '完成报告'));

    await repository.setStatus(task.id, TaskStatus.done);
    final completed = await repository.get(task.id);

    expect(completed.status, TaskStatus.done);
    expect(completed.completedAt, isNotNull);
    expect(completed.version, 2);
  });

  test('archived task is excluded unless explicitly requested', () async {
    final task = await repository.create(const TaskDraft(title: '旧任务'));

    await repository.archive(task.id);

    expect(await repository.list(), isEmpty);
    expect(await repository.list(includeArchived: true), hasLength(1));
  });

  test('empty task title is rejected without a database write', () async {
    expect(
      () => repository.create(const TaskDraft(title: '   ')),
      throwsArgumentError,
    );
    expect(await repository.list(includeArchived: true), isEmpty);
  });
  test('completing a repeating task creates the next occurrence once',
      () async {
    final task = await repository.create(TaskDraft(
      title: '每日复习',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await repository.setStatus(task.id, TaskStatus.done);
    await repository.setStatus(task.id, TaskStatus.done);

    final tasks = await repository.list();
    expect(tasks, hasLength(2));
    final next = tasks.singleWhere((value) => value.id != task.id);
    expect(
      DateTime.fromMillisecondsSinceEpoch(next.dueAt!, isUtc: true)
          .toLocal()
          .day,
      9,
    );
    expect(next.status, TaskStatus.todo);
  });

  test('completing a task with an extreme repeat interval does not roll back',
      () async {
    final task = await repository.create(TaskDraft(
      title: 'legacy imported repeat',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1000000',
    ));

    await repository.setStatus(task.id, TaskStatus.done);

    final completed = await repository.get(task.id);
    expect(completed.status, TaskStatus.done);
    expect(await repository.list(), hasLength(1));
  });

  test('recompleting a repeating task reuses its persisted next occurrence',
      () async {
    final task = await repository.create(TaskDraft(
      title: '每日复习',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await (database.update(database.tasks)
          ..where((row) => row.id.equals(task.id)))
        .write(const TasksCompanion(
      metadata: Value('{"custom":{"label":"保留"},"source":"manual"}'),
    ));
    await repository.setStatus(task.id, TaskStatus.done);
    final next = (await repository.list()).singleWhere((row) => row.id != task.id);
    await repository.setStatus(task.id, TaskStatus.todo);
    await TaskRepository(database).setStatus(task.id, TaskStatus.done);

    expect(await repository.list(), hasLength(2));
    expect((await repository.get(next.id)).dueAt,
        DateTime(2026, 8, 9, 20).millisecondsSinceEpoch);
    final metadata = jsonDecode((await repository.get(task.id)).metadata) as Map;
    expect(metadata['custom'], {'label': '保留'});
    expect(metadata['source'], 'manual');
    await repository.setStatus(next.id, TaskStatus.done);
    expect(await repository.list(), hasLength(3));
  });

  test('concurrent completion creates only one next occurrence', () async {
    final task = await repository.create(TaskDraft(
      title: '每日复习',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await Future.wait([
      repository.setStatus(task.id, TaskStatus.done),
      repository.setStatus(task.id, TaskStatus.done),
    ]);

    expect(await repository.list(), hasLength(2));
  });

  test('recompletion does not restore a deleted next occurrence', () async {
    final task = await repository.create(TaskDraft(
      title: '每日复习',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await repository.setStatus(task.id, TaskStatus.done);
    final next = (await repository.list()).singleWhere((row) => row.id != task.id);
    await repository.delete(next.id);
    await repository.setStatus(task.id, TaskStatus.todo);
    await repository.setStatus(task.id, TaskStatus.done);

    expect(await database.select(database.tasks).get(), hasLength(2));
    expect((await repository.get(next.id)).deletedAt, isNotNull);
  });

  test('repeating completion tolerates legacy metadata without discarding it',
      () async {
    final task = await repository.create(TaskDraft(
      title: '旧任务',
      dueAt: DateTime(2026, 8, 8, 20),
      repeatRule: 'FREQ=DAILY;INTERVAL=1',
    ));
    await (database.update(database.tasks)
          ..where((row) => row.id.equals(task.id)))
        .write(const TasksCompanion(metadata: Value('legacy text')));
    await repository.setStatus(task.id, TaskStatus.done);
    await repository.setStatus(task.id, TaskStatus.todo);
    await repository.setStatus(task.id, TaskStatus.done);

    expect(await repository.list(), hasLength(2));
    final metadata = jsonDecode((await repository.get(task.id)).metadata) as Map;
    expect(metadata.values, contains('legacy text'));
  });

  test('postpone revalidates only the selected filtered task ids', () async {
    for (final id in ['project-a', 'project-b']) {
      await database.into(database.projects).insert(
            ProjectsCompanion.insert(id: Value(id), name: id),
          );
    }
    final now = DateTime.now();
    final oldDue = DateTime(now.year, now.month, now.day - 1, 18);
    final fixtures = <TaskEntry>[];
    for (final draft in [
      TaskDraft(title: 'eligible', projectId: 'project-a',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'other project', projectId: 'project-b',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'other category', projectId: 'project-a',
          category: TaskCategory.life, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'other priority', projectId: 'project-a',
          category: TaskCategory.work, priority: 1, dueAt: oldDue),
      TaskDraft(title: 'canceled', projectId: 'project-a',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'done', projectId: 'project-a',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'archived', projectId: 'project-a',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'deleted', projectId: 'project-a',
          category: TaskCategory.work, priority: 3, dueAt: oldDue),
      TaskDraft(title: 'future', projectId: 'project-a',
          category: TaskCategory.work, priority: 3,
          dueAt: DateTime(now.year, now.month, now.day + 1, 18)),
    ]) {
      fixtures.add(await repository.create(draft));
    }
    final selected = await repository.list(
      projectId: 'project-a', category: TaskCategory.work, priority: 3,
    );
    await repository.setStatus(fixtures[4].id, TaskStatus.canceled);
    await repository.setStatus(fixtures[5].id, TaskStatus.done);
    await repository.archive(fixtures[6].id);
    await repository.delete(fixtures[7].id);

    final count = await repository.postponeOverdueTasks(
      now, taskIds: [...selected.map((row) => row.id), fixtures.first.id, 'missing'],
    );

    expect(count, 1);
    expect((await repository.get(fixtures.first.id)).dueAt,
        DateTime(now.year, now.month, now.day, 18).millisecondsSinceEpoch);
    for (final unchanged in fixtures.skip(1)) {
      expect((await repository.get(unchanged.id)).dueAt, unchanged.dueAt);
    }
    expect(await repository.postponeOverdueTasks(now, taskIds: []), 0);
  });

  test('batch postponement rolls back all dates when one update fails', () async {
    final now = DateTime.now();
    final oldDue = DateTime(now.year, now.month, now.day - 1, 18);
    final first = await repository.create(TaskDraft(title: 'first', dueAt: oldDue));
    final second = await repository.create(TaskDraft(title: 'second', dueAt: oldDue));
    final targetMillis = DateTime(now.year, now.month, now.day, 18)
        .millisecondsSinceEpoch;
    await database.customStatement('''
      CREATE TRIGGER reject_second_postpone BEFORE UPDATE ON tasks
      WHEN NEW.due_at = $targetMillis AND
        EXISTS (SELECT 1 FROM tasks WHERE due_at = $targetMillis)
      BEGIN SELECT RAISE(ABORT, 'reject second update'); END
    ''');

    await expectLater(
      repository.postponeOverdueTasks(now, taskIds: [first.id, second.id]),
      throwsA(isA<Exception>()),
    );

    expect((await repository.get(first.id)).dueAt, oldDue.millisecondsSinceEpoch);
    expect((await repository.get(second.id)).dueAt, oldDue.millisecondsSinceEpoch);
    expect(await database.select(database.changeLogs).get(), hasLength(2));
  });

  test('filters by category priority date and parent task', () async {
    final parent = await repository.create(TaskDraft(
      title: 'parent',
      category: TaskCategory.work,
      priority: 3,
      dueAt: DateTime(2026, 8, 9, 12),
    ));
    await repository.create(TaskDraft(
      title: 'child',
      category: TaskCategory.work,
      priority: 3,
      dueAt: DateTime(2026, 8, 9, 18),
      parentTaskId: parent.id,
    ));
    await repository.create(TaskDraft(
      title: 'other',
      category: TaskCategory.life,
      priority: 1,
      dueAt: DateTime(2026, 8, 10),
    ));

    final filtered = await repository.list(
      category: TaskCategory.work,
      priority: 3,
      dueFrom: DateTime(2026, 8, 9),
      dueBefore: DateTime(2026, 8, 10),
    );
    expect(
        filtered.map((task) => task.title), containsAll(['parent', 'child']));
    expect(
      (await repository.list(parentTaskId: parent.id)).single.title,
      'child',
    );
    expect(
      (await repository.list(rootsOnly: true)).map((task) => task.title),
      containsAll(['parent', 'other']),
    );
  });

  test('timed task preserves its start and end and delete hides it', () async {
    final task = await repository.create(TaskDraft(
      title: 'timed',
      startAt: DateTime(2026, 8, 10, 19),
      dueAt: DateTime(2026, 8, 10, 21),
    ));
    expect(task.startAt, isNotNull);
    expect(
        task.dueAt! - task.startAt!, const Duration(hours: 2).inMilliseconds);

    await repository.delete(task.id);
    expect(await repository.list(includeArchived: true), isEmpty);
  });

  test('task hierarchy allows five levels and rejects a sixth', () async {
    TaskEntry current =
        await repository.create(const TaskDraft(title: 'level 1'));
    for (var level = 2; level <= 5; level++) {
      current = await repository.create(TaskDraft(
        title: 'level $level',
        parentTaskId: current.id,
      ));
      expect(await repository.depthOf(current.id), level);
    }

    await expectLater(
      repository.create(TaskDraft(title: 'level 6', parentTaskId: current.id)),
      throwsStateError,
    );
  });

  test('archiving a parent promotes direct children and keeps descendants',
      () async {
    final root = await repository.create(const TaskDraft(title: 'level 1'));
    final second = await repository.create(
      TaskDraft(title: 'level 2', parentTaskId: root.id),
    );
    final third = await repository.create(
      TaskDraft(title: 'level 3', parentTaskId: second.id),
    );
    final fourth = await repository.create(
      TaskDraft(title: 'level 4', parentTaskId: third.id),
    );

    await repository.archive(root.id);

    expect((await repository.get(second.id)).parentTaskId, isNull);
    expect((await repository.get(third.id)).parentTaskId, second.id);
    expect(await repository.depthOf(fourth.id), 3);
    final newFourth = await repository.create(
      TaskDraft(title: 'new level 4', parentTaskId: fourth.id),
    );
    final newFifth = await repository.create(
      TaskDraft(title: 'new level 5', parentTaskId: newFourth.id),
    );
    expect(await repository.depthOf(newFifth.id), 5);
  });

  test('moving a task under its descendant is rejected as a cycle', () async {
    final parent = await repository.create(const TaskDraft(title: 'parent'));
    final child = await repository.create(
      TaskDraft(title: 'child', parentTaskId: parent.id),
    );

    await expectLater(
      repository.update(
        parent.id,
        TaskDraft(title: 'parent', parentTaskId: child.id),
      ),
      throwsStateError,
    );
  });

  test('bulk archive promotes children and ignores duplicate ids', () async {
    final first = await repository.create(const TaskDraft(title: 'first'));
    final child = await repository.create(
      TaskDraft(title: 'child', parentTaskId: first.id),
    );
    final second = await repository.create(const TaskDraft(title: 'second'));

    await repository.archiveMany([first.id, second.id, first.id]);

    expect(await repository.list(), hasLength(1));
    expect((await repository.get(child.id)).parentTaskId, isNull);
    expect((await repository.get(first.id)).status, TaskStatus.archived);
    expect((await repository.get(second.id)).status, TaskStatus.archived);
  });

  test('bulk delete promotes unselected children and ignores duplicate ids',
      () async {
    final first = await repository.create(const TaskDraft(title: 'first'));
    final child = await repository.create(
      TaskDraft(title: 'child', parentTaskId: first.id),
    );
    final second = await repository.create(const TaskDraft(title: 'second'));

    await repository.deleteMany([first.id, second.id, first.id]);

    expect((await repository.list()).map((task) => task.title), ['child']);
    expect((await repository.get(child.id)).parentTaskId, isNull);
    expect((await repository.get(first.id)).deletedAt, isNotNull);
    expect((await repository.get(second.id)).deletedAt, isNotNull);
  });
}
