import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late ProjectRepository projects;
  late TaskRepository tasks;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    projects = ProjectRepository(database);
    tasks = TaskRepository(database);
  });

  tearDown(() => database.close());

  test('automatic progress is derived from linked active tasks', () async {
    final project = await projects.create(
      const ProjectDraft(name: '发布 LifeHub'),
    );
    final first = await tasks.create(
      TaskDraft(title: '完成界面', projectId: project.id),
    );
    await tasks.create(TaskDraft(title: '完成测试', projectId: project.id));

    expect(await projects.progress(project.id), 0);
    await tasks.setStatus(first.id, TaskStatus.done);
    expect(await projects.progress(project.id), 0.5);
  });

  test('archiving a project keeps its linked tasks intact', () async {
    final project = await projects.create(const ProjectDraft(name: '旧项目'));
    final task = await tasks.create(
      TaskDraft(title: '保留的任务', projectId: project.id),
    );

    await projects.archive(project.id);

    expect(await projects.list(), isEmpty);
    expect((await tasks.get(task.id)).projectId, project.id);
  });

  test('deleted project is excluded even from archived results', () async {
    final project = await projects.create(const ProjectDraft(name: '删除项目'));
    await projects.delete(project.id);
    expect(await projects.list(includeArchived: true), isEmpty);
  });
}
