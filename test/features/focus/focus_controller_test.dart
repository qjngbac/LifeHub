import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/focus/application/focus_controller.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';

void main() {
  test('controller loads once and reports automatic completion once', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FocusRepository(database);
    final start = DateTime.utc(2026, 8, 9, 9);
    await repository.start(const FocusDraft(plannedMinutes: 25), now: start);
    var completed = 0;
    final controller = FocusController(
      repository,
      onCompleted: (_) async => completed++,
    );
    await controller.load();

    expect(
        await controller.tick(start.add(const Duration(minutes: 24))), isFalse);
    expect(
        await controller.tick(start.add(const Duration(minutes: 25))), isTrue);
    expect(
        await controller.tick(start.add(const Duration(minutes: 26))), isFalse);
    expect(completed, 1);
  });
}
