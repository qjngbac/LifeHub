import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class MaintenanceDraft {
  const MaintenanceDraft({
    required this.title,
    required this.intervalDays,
    required this.nextDueAt,
    this.householdItemId,
    this.reminderDays = 1,
    this.notes,
  });

  final String title;
  final int intervalDays;
  final DateTime nextDueAt;
  final String? householdItemId;
  final int reminderDays;
  final String? notes;
}

class MaintenanceRepository {
  MaintenanceRepository(this._database);
  final AppDatabase _database;

  Future<MaintenancePlanEntry> create(MaintenanceDraft draft) async {
    if (draft.title.trim().isEmpty) {
      throw ArgumentError.value(draft.title, 'title');
    }
    if (draft.intervalDays <= 0 || draft.reminderDays < 0) {
      throw ArgumentError('Maintenance interval is invalid.');
    }
    if (draft.householdItemId != null) {
      final item = await (_database.select(_database.householdItems)
            ..where((row) =>
                row.id.equals(draft.householdItemId!) & row.deletedAt.isNull()))
          .getSingleOrNull();
      if (item == null) throw StateError('Household item not found.');
    }
    return _database.into(_database.maintenancePlans).insertReturning(
          MaintenancePlansCompanion.insert(
            householdItemId: Value(draft.householdItemId),
            title: draft.title.trim(),
            intervalDays: draft.intervalDays,
            nextDueAt: draft.nextDueAt.millisecondsSinceEpoch,
            reminderDays: Value(draft.reminderDays),
            notes: Value(_optional(draft.notes)),
          ),
        );
  }

  Future<MaintenancePlanEntry> get(String id) async {
    final row = await (_database.select(_database.maintenancePlans)
          ..where((item) => item.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Maintenance plan not found: $id');
    return row;
  }

  Future<List<MaintenancePlanEntry>> list({bool activeOnly = true}) =>
      (_database.select(_database.maintenancePlans)
            ..where((row) {
              var result = row.deletedAt.isNull();
              if (activeOnly) result = result & row.active.equals(true);
              return result;
            })
            ..orderBy([(row) => OrderingTerm.asc(row.nextDueAt)]))
          .get();

  Future<TaskEntry> ensureCurrentTask(String id) async {
    final plan = await get(id);
    if (!plan.active) throw StateError('Maintenance plan is inactive.');
    if (plan.currentTaskId != null) {
      final existing = await (_database.select(_database.tasks)
            ..where((row) =>
                row.id.equals(plan.currentTaskId!) & row.deletedAt.isNull()))
          .getSingleOrNull();
      if (existing != null && existing.status != TaskStatus.done) {
        return existing;
      }
    }
    late TaskEntry task;
    await _database.transaction(() async {
      task = await TaskRepository(_database).create(TaskDraft(
        title: plan.title,
        category: TaskCategory.life,
        dueAt: DateTime.fromMillisecondsSinceEpoch(plan.nextDueAt),
      ));
      await RelationRepository(_database).link(
        EntityReference(type: 'MAINTENANCE', id: plan.id),
        EntityReference(type: 'TASK', id: task.id),
        relationType: 'ACTION',
      );
      await (_database.update(_database.maintenancePlans)
            ..where((row) => row.id.equals(id)))
          .write(MaintenancePlansCompanion(currentTaskId: Value(task.id)));
    });
    return task;
  }

  Future<MaintenancePlanEntry> completePlan(
    String id, {
    DateTime? completedAt,
    String? notes,
  }) async {
    final plan = await get(id);
    final completed = completedAt ?? DateTime.now();
    final next = completed.add(Duration(days: plan.intervalDays));
    await _database.transaction(() async {
      await _database.into(_database.maintenanceLogs).insert(
            MaintenanceLogsCompanion.insert(
              planId: id,
              completedAt: completed.millisecondsSinceEpoch,
              notes: Value(_optional(notes)),
            ),
          );
      if (plan.currentTaskId != null) {
        final task = await (_database.select(_database.tasks)
              ..where((row) => row.id.equals(plan.currentTaskId!)))
            .getSingleOrNull();
        if (task != null && task.status != TaskStatus.done) {
          await TaskRepository(_database)
              .setStatus(plan.currentTaskId!, TaskStatus.done);
        }
      }
      await (_database.update(_database.maintenancePlans)
            ..where((row) => row.id.equals(id)))
          .write(MaintenancePlansCompanion(
        lastCompletedAt: Value(completed.millisecondsSinceEpoch),
        nextDueAt: Value(next.millisecondsSinceEpoch),
        currentTaskId: const Value(null),
        updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        version: Value(plan.version + 1),
      ));
    });
    return get(id);
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
