import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/household/data/maintenance_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  test('maintenance creates one task and advances after completion', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = MaintenanceRepository(db);
    final plan = await repository.create(MaintenanceDraft(
      title: '清洗空调滤网',
      intervalDays: 30,
      nextDueAt: DateTime(2026, 8, 15),
    ));

    final first = await repository.ensureCurrentTask(plan.id);
    final second = await repository.ensureCurrentTask(plan.id);
    expect(second.id, first.id);

    await repository.completePlan(
      plan.id,
      completedAt: DateTime(2026, 8, 16),
    );
    final updated = await repository.get(plan.id);
    expect(updated.nextDueAt, DateTime(2026, 9, 15).millisecondsSinceEpoch);
    expect(updated.currentTaskId, isNull);
    expect(await db.select(db.maintenanceLogs).get(), hasLength(1));
  });

  for (final status in [TaskStatus.archived, TaskStatus.canceled, TaskStatus.done]) {
    test('maintenance does not reuse a $status task', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = MaintenanceRepository(db);
      final plan = await repository.create(MaintenanceDraft(
        title: 'maintenance', intervalDays: 30, nextDueAt: DateTime(2026, 8, 15),
      ));
      final previous = await repository.ensureCurrentTask(plan.id);
      await TaskRepository(db).setStatus(previous.id, status);
      final current = await repository.ensureCurrentTask(plan.id);
      expect(current.id, isNot(previous.id));
      expect(current.status, TaskStatus.todo);
      expect((await TaskRepository(db).get(previous.id)).status, status);
      expect(await db.select(db.entityLinks).get(), hasLength(2));
    });

    test('maintenance completes independently of a $status task', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = MaintenanceRepository(db);
      final plan = await repository.create(MaintenanceDraft(
        title: 'maintenance', intervalDays: 30, nextDueAt: DateTime(2026, 8, 15),
      ));
      final task = await repository.ensureCurrentTask(plan.id);
      await TaskRepository(db).setStatus(task.id, status);
      final updated = await repository.completePlan(plan.id,
          completedAt: DateTime(2026, 8, 16), notes: '完成');
      expect(updated.nextDueAt, DateTime(2026, 9, 15).millisecondsSinceEpoch);
      expect(updated.currentTaskId, isNull);
      expect((await TaskRepository(db).get(task.id)).status, status);
      expect((await db.select(db.maintenanceLogs).get()).single.notes, '完成');
    });
  }

  test('maintenance completion preserves a deleted task history', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = MaintenanceRepository(db);
    final plan = await repository.create(MaintenanceDraft(
      title: 'maintenance', intervalDays: 30, nextDueAt: DateTime(2026, 8, 15),
    ));
    final task = await repository.ensureCurrentTask(plan.id);
    await TaskRepository(db).delete(task.id);
    final before = await TaskRepository(db).get(task.id);
    await repository.completePlan(plan.id, completedAt: DateTime(2026, 8, 16));
    final after = await TaskRepository(db).get(task.id);
    expect(after.status, before.status);
    expect(after.deletedAt, before.deletedAt);
    expect(after.version, before.version);
    expect(await db.select(db.maintenanceLogs).get(), hasLength(1));
  });
}
