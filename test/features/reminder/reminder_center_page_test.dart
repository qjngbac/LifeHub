import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/reminder/presentation/reminder_center_page.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  testWidgets('past trigger is shown without claiming delivery was missed', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task = await TaskRepository(
      database,
    ).create(const TaskDraft(title: '已经送达与否未知'));
    await database
        .into(database.reminders)
        .insert(
          RemindersCompanion.insert(
            entityType: 'TASK',
            entityId: task.id,
            notificationId: 10,
            triggerAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: ReminderCenterPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('过去的提醒'), findsOneWidget);
    expect(find.text('已经错过'), findsNothing);
    expect(find.text('已经送达与否未知'), findsOneWidget);
  });
}
