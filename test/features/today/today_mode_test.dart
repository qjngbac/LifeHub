import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/today/application/today_mode.dart';

void main() {
  test('student mode ranks study tasks first without changing the data', () {
    const life = TaskEntry(
      id: 'life',
      createdAt: 1,
      updatedAt: 1,
      version: 1,
      syncState: 0,
      metadata: '{}',
      title: 'life',
      category: TaskCategory.life,
      status: TaskStatus.todo,
      priority: 0,
      sortKey: 0,
    );
    final study = life.copyWith(
      id: 'study',
      title: 'study',
      category: TaskCategory.study,
    );
    final source = [life, study];
    final ranked = TodayModeRanking.tasks(source, {LifeMode.student});
    expect(ranked.first.id, 'study');
    expect(source.first.id, 'life');
  });
}
