import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/event/domain/recurrence.dart';
import 'package:uuid/uuid.dart';

abstract final class TaskStatus {
  static const todo = 'TODO';
  static const inProgress = 'IN_PROGRESS';
  static const done = 'DONE';
  static const canceled = 'CANCELED';
  static const archived = 'ARCHIVED';
}

abstract final class TaskCategory {
  static const study = 'STUDY';
  static const work = 'WORK';
  static const life = 'LIFE';
  static const outdoor = 'OUTDOOR';
}

class TaskDraft {
  const TaskDraft({
    required this.title,
    this.description,
    this.category = TaskCategory.life,
    this.priority = 0,
    this.dueAt,
    this.startAt,
    this.projectId,
    this.parentTaskId,
    this.repeatRule,
  });

  final String title;
  final String? description;
  final String category;
  final int priority;
  final DateTime? dueAt;
  final DateTime? startAt;
  final String? projectId;
  final String? parentTaskId;
  final String? repeatRule;
}

class TaskRepository {
  TaskRepository(this._database);

  final AppDatabase _database;

  Future<TaskEntry> create(TaskDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(
          draft.title, 'title', 'Task title is required.');
    }
    if (draft.priority < 0 || draft.priority > 4) {
      throw ArgumentError.value(draft.priority, 'priority');
    }
    await _validateReferences(draft);
    await _validateHierarchy(parentId: draft.parentTaskId);

    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.tasks).insert(
            TasksCompanion.insert(
              id: Value(id),
              title: title,
              description: Value(_trimmedOrNull(draft.description)),
              category: Value(draft.category),
              priority: Value(draft.priority),
              dueAt: Value(draft.dueAt?.toUtc().millisecondsSinceEpoch),
              startAt: Value(draft.startAt?.toUtc().millisecondsSinceEpoch),
              projectId: Value(draft.projectId),
              parentTaskId: Value(draft.parentTaskId),
              repeatRule: Value(draft.repeatRule),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<TaskEntry> get(String id) async {
    final task = await (_database.select(_database.tasks)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (task == null) {
      throw StateError('Task not found: $id');
    }
    return task;
  }

  Future<int> depthOf(String id) async {
    var current = await get(id);
    var depth = 1;
    final visited = <String>{id};
    while (current.parentTaskId != null) {
      if (!visited.add(current.parentTaskId!)) {
        throw StateError('Task hierarchy contains a cycle.');
      }
      current = await get(current.parentTaskId!);
      depth++;
    }
    return depth;
  }

  Future<TaskEntry> update(String id, TaskDraft draft) async {
    final current = await get(id);
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    if (draft.priority < 0 || draft.priority > 4) {
      throw ArgumentError.value(draft.priority, 'priority');
    }
    if (draft.parentTaskId == id) {
      throw ArgumentError('Task cannot be its own parent.');
    }
    await _validateReferences(draft);
    await _validateHierarchy(parentId: draft.parentTaskId, taskId: id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.tasks)
            ..where((row) => row.id.equals(id)))
          .write(TasksCompanion(
        title: Value(title),
        description: Value(_trimmedOrNull(draft.description)),
        category: Value(draft.category),
        priority: Value(draft.priority),
        dueAt: Value(draft.dueAt?.toUtc().millisecondsSinceEpoch),
        startAt: Value(draft.startAt?.toUtc().millisecondsSinceEpoch),
        projectId: Value(draft.projectId),
        parentTaskId: Value(draft.parentTaskId),
        repeatRule: Value(draft.repeatRule),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<TaskEntry>> list({
    bool includeArchived = false,
    String? projectId,
    String? category,
    int? priority,
    DateTime? dueFrom,
    DateTime? dueBefore,
    String? parentTaskId,
    bool rootsOnly = false,
  }) {
    final query = _database.select(_database.tasks)
      ..where((row) {
        Expression<bool> filter = row.deletedAt.isNull();
        if (!includeArchived) {
          filter = filter & row.status.equals(TaskStatus.archived).not();
        }
        if (projectId != null) {
          filter = filter & row.projectId.equals(projectId);
        }
        if (category != null) filter = filter & row.category.equals(category);
        if (priority != null) filter = filter & row.priority.equals(priority);
        if (dueFrom != null) {
          filter = filter &
              row.dueAt
                  .isBiggerOrEqualValue(dueFrom.toUtc().millisecondsSinceEpoch);
        }
        if (dueBefore != null) {
          filter = filter &
              row.dueAt
                  .isSmallerThanValue(dueBefore.toUtc().millisecondsSinceEpoch);
        }
        if (parentTaskId != null) {
          filter = filter & row.parentTaskId.equals(parentTaskId);
        } else if (rootsOnly) {
          filter = filter & row.parentTaskId.isNull();
        }
        return filter;
      })
      ..orderBy([
        (row) => OrderingTerm(expression: row.sortKey),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.get();
  }

  Stream<List<TaskEntry>> watch({String? projectId}) {
    final query = _database.select(_database.tasks)
      ..where((row) {
        var filter = row.deletedAt.isNull() &
            row.status.equals(TaskStatus.archived).not();
        if (projectId != null) {
          filter = filter & row.projectId.equals(projectId);
        }
        return filter;
      })
      ..orderBy([
        (row) => OrderingTerm(expression: row.sortKey),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.watch();
  }

  Future<void> setStatus(String id, String status, {DateTime? now}) async {
    if (status == TaskStatus.archived) {
      await _archivePromotingChildren(id);
      return;
    }
    final current = await get(id);
    _validateTransition(current.status, status);
    if (current.status == status) {
      return;
    }
    final nowMillis = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.tasks)
            ..where((row) => row.id.equals(id)))
          .write(
        TasksCompanion(
          status: Value(status),
          completedAt: Value(status == TaskStatus.done ? nowMillis : null),
          updatedAt: Value(nowMillis),
          version: Value(current.version + 1),
        ),
      );
      await _log(id, 'UPDATE');
      if (status == TaskStatus.done && current.repeatRule != null) {
        await _createNextOccurrence(current);
      }
    });
  }

  Future<void> archive(String id) => setStatus(id, TaskStatus.archived);

  Future<void> archiveMany(Iterable<String> ids) async {
    for (final id in ids.toSet()) {
      await archive(id);
    }
  }

  Future<void> _archivePromotingChildren(String id) async {
    final current = await get(id);
    _validateTransition(current.status, TaskStatus.archived);
    if (current.status == TaskStatus.archived) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      final children = await (_database.select(_database.tasks)
            ..where(
                (row) => row.parentTaskId.equals(id) & row.deletedAt.isNull()))
          .get();
      for (final child in children) {
        await (_database.update(_database.tasks)
              ..where((row) => row.id.equals(child.id)))
            .write(TasksCompanion(
          parentTaskId: Value(current.parentTaskId),
          updatedAt: Value(now),
          version: Value(child.version + 1),
        ));
        await _log(child.id, 'UPDATE');
      }
      await (_database.update(_database.tasks)
            ..where((row) => row.id.equals(id)))
          .write(TasksCompanion(
        status: const Value(TaskStatus.archived),
        completedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
  }

  Future<void> delete(String id) => deleteMany([id]);

  Future<void> deleteMany(Iterable<String> ids) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) return;
    final selected = await (_database.select(_database.tasks)
          ..where((row) => row.id.isIn(uniqueIds) & row.deletedAt.isNull()))
        .get();
    if (selected.isEmpty) return;
    final selectedById = {for (final task in selected) task.id: task};
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      final children = await (_database.select(_database.tasks)
            ..where((row) =>
                row.parentTaskId.isIn(uniqueIds) & row.deletedAt.isNull()))
          .get();
      for (final child in children) {
        if (uniqueIds.contains(child.id)) continue;
        var parentId = child.parentTaskId;
        final visited = <String>{};
        while (parentId != null && uniqueIds.contains(parentId)) {
          if (!visited.add(parentId)) {
            parentId = null;
            break;
          }
          parentId = selectedById[parentId]?.parentTaskId;
        }
        await (_database.update(_database.tasks)
              ..where((row) => row.id.equals(child.id)))
            .write(TasksCompanion(
          parentTaskId: Value(parentId),
          updatedAt: Value(now),
          version: Value(child.version + 1),
        ));
        await _log(child.id, 'UPDATE');
      }
      for (final current in selected) {
        await (_database.update(_database.tasks)
              ..where((row) => row.id.equals(current.id)))
            .write(TasksCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(current.version + 1),
        ));
        await _log(current.id, 'DELETE');
      }
    });
  }

  Future<void> restore(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.tasks)
            ..where((row) => row.id.equals(id)))
          .write(TasksCompanion(
        status: const Value(TaskStatus.todo),
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'RESTORE');
    });
  }

  Future<void> _log(String id, String operation) {
    return _database.into(_database.changeLogs).insert(
          ChangeLogsCompanion.insert(
            entityType: 'TASK',
            entityId: id,
            operation: operation,
          ),
        );
  }

  Future<void> _createNextOccurrence(TaskEntry current) async {
    final sourceMillis = current.dueAt ?? current.startAt;
    if (sourceMillis == null) {
      return;
    }
    final source =
        DateTime.fromMillisecondsSinceEpoch(sourceMillis, isUtc: true);
    final next = Recurrence.expandStarts(
      sourceStart: source,
      rule: current.repeatRule,
      windowStart: source.add(const Duration(milliseconds: 1)),
      windowEnd: source.add(const Duration(days: 3660)),
    ).first;
    final delta = next.difference(source);
    final nextId = const Uuid().v4();
    await _database.into(_database.tasks).insert(
          TasksCompanion.insert(
            id: Value(nextId),
            title: current.title,
            description: Value(current.description),
            category: Value(current.category),
            priority: Value(current.priority),
            dueAt: Value(current.dueAt == null
                ? null
                : current.dueAt! + delta.inMilliseconds),
            startAt: Value(current.startAt == null
                ? null
                : current.startAt! + delta.inMilliseconds),
            projectId: Value(current.projectId),
            parentTaskId: Value(current.parentTaskId),
            repeatRule: Value(current.repeatRule),
          ),
        );
    await _log(nextId, 'CREATE');
  }

  static String? _trimmedOrNull(String? source) {
    final value = source?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _validateReferences(TaskDraft draft) async {
    const categories = {
      TaskCategory.study,
      TaskCategory.work,
      TaskCategory.life,
      TaskCategory.outdoor,
    };
    if (!categories.contains(draft.category)) {
      throw ArgumentError.value(draft.category, 'category');
    }
    if (draft.repeatRule != null) {
      final source = draft.dueAt ?? draft.startAt;
      if (source == null) {
        throw ArgumentError('Repeating task requires a date.');
      }
      Recurrence.expandStarts(
        sourceStart: source,
        rule: draft.repeatRule,
        windowStart: source,
        windowEnd: source.add(const Duration(days: 1)),
      );
    }
    if (draft.projectId != null) {
      final exists = await (_database.select(_database.projects)
            ..where((row) =>
                row.id.equals(draft.projectId!) & row.deletedAt.isNull()))
          .getSingleOrNull();
      if (exists == null) throw StateError('Project not found.');
    }
    if (draft.parentTaskId != null) {
      final parent = await (_database.select(_database.tasks)
            ..where((row) =>
                row.id.equals(draft.parentTaskId!) & row.deletedAt.isNull()))
          .getSingleOrNull();
      if (parent == null) throw StateError('Parent task not found.');
    }
  }

  Future<void> _validateHierarchy({String? parentId, String? taskId}) async {
    var depth = 1;
    var currentId = parentId;
    final visited = <String>{if (taskId != null) taskId};
    while (currentId != null) {
      if (!visited.add(currentId)) {
        throw StateError('Task hierarchy cannot contain a cycle.');
      }
      final parent = await get(currentId);
      if (parent.status == TaskStatus.archived) {
        throw StateError('Cannot add a subtask to an archived task.');
      }
      depth++;
      currentId = parent.parentTaskId;
    }
    final subtreeHeight = taskId == null ? 1 : await _subtreeHeight(taskId);
    if (depth + subtreeHeight - 1 > 5) {
      throw StateError('Tasks support at most five levels.');
    }
  }

  Future<int> _subtreeHeight(String rootId) async {
    final rows = await (_database.select(_database.tasks)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final children = <String, List<String>>{};
    for (final row in rows) {
      if (row.parentTaskId != null) {
        children.putIfAbsent(row.parentTaskId!, () => []).add(row.id);
      }
    }

    int visit(String id, Set<String> path) {
      if (!path.add(id)) throw StateError('Task hierarchy contains a cycle.');
      var height = 1;
      for (final child in children[id] ?? const <String>[]) {
        final childHeight = 1 + visit(child, {...path});
        if (childHeight > height) height = childHeight;
      }
      return height;
    }

    return visit(rootId, <String>{});
  }

  static void _validateTransition(String from, String to) {
    const allowed = <String, Set<String>>{
      TaskStatus.todo: {
        TaskStatus.inProgress,
        TaskStatus.done,
        TaskStatus.canceled,
        TaskStatus.archived,
      },
      TaskStatus.inProgress: {
        TaskStatus.todo,
        TaskStatus.done,
        TaskStatus.canceled,
        TaskStatus.archived,
      },
      TaskStatus.done: {TaskStatus.todo, TaskStatus.archived},
      TaskStatus.canceled: {TaskStatus.todo, TaskStatus.archived},
      TaskStatus.archived: {TaskStatus.todo},
    };
    if (from == to) {
      return;
    }
    if (!(allowed[from]?.contains(to) ?? false)) {
      throw StateError('Invalid task transition: $from -> $to');
    }
  }
}
