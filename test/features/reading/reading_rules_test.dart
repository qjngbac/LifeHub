import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';

void main() {
  test('unknown total can advance without showing a false percentage', () {
    final update = ReadingProgressRules.update(
      current: 10,
      next: 20,
      total: null,
      status: ReadingStatus.reading,
      now: DateTime(2026, 8, 11),
    );
    expect(update.current, 20);
    expect(update.completedAt, isNull);
    expect(ReadingProgressRules.fraction(current: 20, total: null), isNull);
  });

  test('completion and rollback update status', () {
    final now = DateTime(2026, 8, 11);
    final complete = ReadingProgressRules.update(
      current: 80,
      next: 100,
      total: 100,
      status: ReadingStatus.reading,
      now: now,
    );
    expect(complete.status, ReadingStatus.completed);
    expect(complete.completedAt, now);
    final rollback = ReadingProgressRules.update(
      current: 100,
      next: 90,
      total: 100,
      status: ReadingStatus.completed,
      now: now,
    );
    expect(rollback.status, ReadingStatus.reading);
    expect(rollback.completedAt, isNull);
  });
}
