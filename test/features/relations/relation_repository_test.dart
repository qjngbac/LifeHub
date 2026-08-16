import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';

void main() {
  late AppDatabase database;
  late RelationRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RelationRepository(database);
    await database.into(database.tasks).insert(
          TasksCompanion.insert(
            id: const Value('task-1'),
            title: '准备材料',
          ),
        );
    await database.into(database.projects).insert(
          ProjectsCompanion.insert(
            id: const Value('project-1'),
            name: '旅行计划',
          ),
        );
  });

  tearDown(() => database.close());

  test('stores one canonical link and finds it from either endpoint', () async {
    const task = EntityReference(type: 'TASK', id: 'task-1');
    const project = EntityReference(type: 'PROJECT', id: 'project-1');

    await repository.link(
      task,
      project,
      relationType: 'SUPPORTS',
      note: '出发前完成',
    );
    await repository.link(project, task);

    expect(await database.select(database.entityLinks).get(), hasLength(1));
    final taskRelations = await repository.relationsFor(task);
    final projectRelations = await repository.relationsFor(project);
    expect(taskRelations.single.entity.title, '旅行计划');
    expect(projectRelations.single.entity.title, '准备材料');
    expect(taskRelations.single.relationType, 'SUPPORTS');
    expect(taskRelations.single.note, '出发前完成');
  });

  test('rejects self links and soft unlinks from either direction', () async {
    const task = EntityReference(type: 'TASK', id: 'task-1');
    const project = EntityReference(type: 'PROJECT', id: 'project-1');

    expect(() => repository.link(task, task), throwsArgumentError);
    await repository.link(task, project);
    await repository.unlink(project, task);

    expect(await repository.relationsFor(task), isEmpty);
    expect((await database.select(database.entityLinks).get()).single.deletedAt,
        isNotNull);
  });
}
