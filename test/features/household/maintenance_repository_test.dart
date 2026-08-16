import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/household/data/maintenance_repository.dart';

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
}
