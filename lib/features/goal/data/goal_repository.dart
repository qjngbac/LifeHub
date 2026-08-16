import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:uuid/uuid.dart';

abstract final class GoalProgressMode {
  static const manual = 'MANUAL';
  static const milestone = 'MILESTONE';
  static const task = 'TASK';
  static const project = 'PROJECT';
}

abstract final class GoalStatus {
  static const draft = 'DRAFT';
  static const active = 'ACTIVE';
  static const paused = 'PAUSED';
  static const completed = 'COMPLETED';
  static const abandoned = 'ABANDONED';
  static const archived = 'ARCHIVED';
}

class GoalDraft {
  const GoalDraft({
    required this.name,
    this.description,
    this.category = 'LIFE',
    this.color = '#8B79C6',
    this.status = GoalStatus.active,
    this.startAt,
    this.targetAt,
    this.progressMode = GoalProgressMode.milestone,
    this.manualProgress,
  });

  final String name;
  final String? description;
  final String category;
  final String color;
  final String status;
  final DateTime? startAt;
  final DateTime? targetAt;
  final String progressMode;
  final double? manualProgress;
}

class GoalRepository {
  GoalRepository(this._database);

  final AppDatabase _database;

  Future<GoalEntry> create(GoalDraft draft) async {
    _validate(draft);
    final id = const Uuid().v4();
    await _database.into(_database.goals).insert(GoalsCompanion.insert(
          id: Value(id),
          name: draft.name.trim(),
          description: Value(_optional(draft.description)),
          category: Value(draft.category),
          color: Value(draft.color),
          status: Value(draft.status),
          startAt: Value(draft.startAt?.toUtc().millisecondsSinceEpoch),
          targetAt: Value(draft.targetAt?.toUtc().millisecondsSinceEpoch),
          progressMode: Value(draft.progressMode),
          manualProgress: Value(draft.manualProgress),
        ));
    await _log('GOAL', id, 'CREATE');
    return get(id);
  }

  Future<GoalEntry> get(String id) async {
    final row = await (_database.select(_database.goals)
          ..where((value) => value.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Goal not found: $id');
    return row;
  }

  Future<List<GoalEntry>> list({bool includeArchived = false}) {
    final query = _database.select(_database.goals)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (!includeArchived) {
          filter = filter & row.status.equals(GoalStatus.archived).not();
        }
        return filter;
      })
      ..orderBy([
        (row) => OrderingTerm(expression: row.targetAt),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.get();
  }

  Future<MilestoneEntry> addMilestone(
    String goalId,
    String name, {
    DateTime? targetAt,
    String? note,
  }) async {
    await get(goalId);
    final value = name.trim();
    if (value.isEmpty) throw ArgumentError.value(name, 'name');
    final maxSort = _database.milestones.sortKey.max();
    final result = await (_database.selectOnly(_database.milestones)
          ..addColumns([maxSort])
          ..where(_database.milestones.goalId.equals(goalId) &
              _database.milestones.deletedAt.isNull()))
        .getSingle();
    final id = const Uuid().v4();
    await _database.into(_database.milestones).insert(
          MilestonesCompanion.insert(
            id: Value(id),
            goalId: goalId,
            name: value,
            targetAt: Value(targetAt?.toUtc().millisecondsSinceEpoch),
            sortKey: Value((result.read(maxSort) ?? -1) + 1),
            note: Value(_optional(note)),
          ),
        );
    await _log('MILESTONE', id, 'CREATE');
    return (_database.select(_database.milestones)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<MilestoneEntry>> milestones(String goalId) =>
      (_database.select(_database.milestones)
            ..where(
              (row) => row.goalId.equals(goalId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm(expression: row.sortKey)]))
          .get();

  Future<void> completeMilestone(
    String id, {
    required bool completed,
  }) async {
    final current = await (_database.select(_database.milestones)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) throw StateError('Milestone not found.');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.milestones)
          ..where((row) => row.id.equals(id)))
        .write(MilestonesCompanion(
      completedAt: Value(completed ? now : null),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  Future<void> link(
    String goalId,
    String targetType,
    String targetId,
  ) async {
    await get(goalId);
    final existing = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sourceType.equals('GOAL') &
              row.sourceId.equals(goalId) &
              row.targetType.equals(targetType) &
              row.targetId.equals(targetId)))
        .getSingleOrNull();
    if (existing != null) return;
    await _database.into(_database.entityLinks).insert(
          EntityLinksCompanion.insert(
            sourceType: 'GOAL',
            sourceId: goalId,
            targetType: targetType,
            targetId: targetId,
          ),
        );
  }

  Future<List<EntityLinkEntry>> links(String goalId) =>
      (_database.select(_database.entityLinks)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.sourceType.equals('GOAL') &
                row.sourceId.equals(goalId)))
          .get();

  Future<void> unlink(
    String goalId,
    String targetType,
    String targetId,
  ) async {
    await get(goalId);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sourceType.equals('GOAL') &
              row.sourceId.equals(goalId) &
              row.targetType.equals(targetType) &
              row.targetId.equals(targetId)))
        .write(EntityLinksCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<GoalEntry> updateManualProgress(String goalId, double progress) async {
    if (progress < 0 || progress > 1) {
      throw ArgumentError.value(progress, 'progress');
    }
    final current = await get(goalId);
    if (current.progressMode != GoalProgressMode.manual) {
      throw StateError('Only manual goals accept manual progress.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.goals)
          ..where((row) => row.id.equals(goalId)))
        .write(GoalsCompanion(
      manualProgress: Value(progress),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
    await _log('GOAL', goalId, 'UPDATE');
    return get(goalId);
  }

  Future<double> progress(String goalId) async {
    final goal = await get(goalId);
    switch (goal.progressMode) {
      case GoalProgressMode.manual:
        return (goal.manualProgress ?? 0).clamp(0, 1);
      case GoalProgressMode.milestone:
        final values = await milestones(goalId);
        if (values.isEmpty) return 0;
        return values.where((value) => value.completedAt != null).length /
            values.length;
      case GoalProgressMode.task:
        final linked = (await links(goalId))
            .where((value) => value.targetType == 'TASK')
            .map((value) => value.targetId)
            .toList();
        if (linked.isEmpty) return 0;
        final tasks = await (_database.select(_database.tasks)
              ..where((row) =>
                  row.id.isIn(linked) &
                  row.deletedAt.isNull() &
                  row.status.equals(TaskStatus.canceled).not()))
            .get();
        if (tasks.isEmpty) return 0;
        return tasks.where((task) => task.status == TaskStatus.done).length /
            tasks.length;
      case GoalProgressMode.project:
        final linked = (await links(goalId))
            .where((value) => value.targetType == 'PROJECT')
            .map((value) => value.targetId)
            .toList();
        if (linked.isEmpty) return 0;
        var sum = 0.0;
        for (final id in linked) {
          sum += await ProjectRepository(_database).progress(id);
        }
        return sum / linked.length;
      default:
        throw StateError('Unknown goal progress mode.');
    }
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.goals)
            ..where((row) => row.id.equals(id)))
          .write(GoalsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await (_database.update(_database.entityLinks)
            ..where((row) =>
                row.sourceType.equals('GOAL') & row.sourceId.equals(id)))
          .write(EntityLinksCompanion(deletedAt: Value(now)));
      await _log('GOAL', id, 'DELETE');
    });
  }

  void _validate(GoalDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw ArgumentError.value(draft.name, 'name');
    }
    const modes = {
      GoalProgressMode.manual,
      GoalProgressMode.milestone,
      GoalProgressMode.task,
      GoalProgressMode.project,
    };
    if (!modes.contains(draft.progressMode)) {
      throw ArgumentError.value(draft.progressMode, 'progressMode');
    }
    if (draft.startAt != null &&
        draft.targetAt != null &&
        draft.targetAt!.isBefore(draft.startAt!)) {
      throw ArgumentError('Goal target date is before start date.');
    }
    if (draft.manualProgress != null &&
        (draft.manualProgress! < 0 || draft.manualProgress! > 1)) {
      throw ArgumentError.value(draft.manualProgress, 'manualProgress');
    }
  }

  Future<void> _log(String type, String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: type,
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
