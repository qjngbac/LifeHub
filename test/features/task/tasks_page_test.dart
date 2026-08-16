import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';

void main() {
  testWidgets('empty task page explains the next action', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(tester, database);

    expect(find.text('还没有任务'), findsOneWidget);
    expect(find.text('创建第一个任务'), findsOneWidget);
  });

  testWidgets('long press enters selection mode and archives selected tasks',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    await repository.create(const TaskDraft(title: '任务一'));
    await repository.create(const TaskDraft(title: '任务二'));
    await _pump(tester, database);

    await tester.longPress(find.text('任务一'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    await tester.tap(find.text('任务二'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(find.byTooltip('归档所选任务'));
    await tester.pumpAndSettle();
    expect(find.text('归档 2 个任务？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '归档'));
    await tester.pumpAndSettle();

    expect(await repository.list(), isEmpty);
    expect(find.text('创建第一个任务'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: const MaterialApp(home: TasksPage()),
  ));
  await tester.pumpAndSettle();
}
