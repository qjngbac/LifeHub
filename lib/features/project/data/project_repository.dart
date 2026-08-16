import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:uuid/uuid.dart';

class ProjectDraft {
  const ProjectDraft({
    required this.name,
    this.description,
    this.color = '#4F46E5',
  });

  final String name;
  final String? description;
  final String color;
}

class ProjectRepository {
  ProjectRepository(this._database);

  final AppDatabase _database;

  Future<ProjectEntry> create(ProjectDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(
          draft.name, 'name', 'Project name is required.');
    }
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.projects).insert(
            ProjectsCompanion.insert(
              id: Value(id),
              name: name,
              description: Value(_trimmedOrNull(draft.description)),
              color: Value(draft.color),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<ProjectEntry> get(String id) async {
    final project = await (_database.select(_database.projects)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (project == null) {
      throw StateError('Project not found: $id');
    }
    return project;
  }

  Future<ProjectEntry> update(String id, ProjectDraft draft) async {
    final current = await get(id);
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError.value(draft.name, 'name');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.projects)
            ..where((row) => row.id.equals(id)))
          .write(ProjectsCompanion(
        name: Value(name),
        description: Value(_trimmedOrNull(draft.description)),
        color: Value(draft.color),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<ProjectEntry>> list({bool includeArchived = false}) {
    final query = _database.select(_database.projects)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (!includeArchived) {
          filter = filter & row.status.equals('ARCHIVED').not();
        }
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.get();
  }

  Stream<List<ProjectEntry>> watch() {
    final query = _database.select(_database.projects)
      ..where(
        (row) => row.deletedAt.isNull() & row.status.equals('ARCHIVED').not(),
      )
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.watch();
  }

  Future<double> progress(String id) async {
    final project = await get(id);
    if (project.progressMode == 'MANUAL') {
      return (project.manualProgress ?? 0).clamp(0.0, 1.0);
    }
    final tasks = await TaskRepository(_database).list(projectId: id);
    final eligible =
        tasks.where((task) => task.status != TaskStatus.canceled).toList();
    if (eligible.isEmpty) {
      return 0;
    }
    final done =
        eligible.where((task) => task.status == TaskStatus.done).length;
    return done / eligible.length;
  }

  Future<void> archive(String id) async {
    final project = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.projects)
            ..where((row) => row.id.equals(id)))
          .write(
        ProjectsCompanion(
          status: const Value('ARCHIVED'),
          updatedAt: Value(now),
          version: Value(project.version + 1),
        ),
      );
      await _log(id, 'UPDATE');
    });
  }

  Future<void> delete(String id) async {
    final project = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.projects)
            ..where((row) => row.id.equals(id)))
          .write(ProjectsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(project.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  Future<void> _log(String id, String operation) {
    return _database.into(_database.changeLogs).insert(
          ChangeLogsCompanion.insert(
            entityType: 'PROJECT',
            entityId: id,
            operation: operation,
          ),
        );
  }

  static String? _trimmedOrNull(String? source) {
    final value = source?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
