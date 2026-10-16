import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';

void main() {
  testWidgets('select all uses refreshed visible tasks during selection',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    await repository.create(const TaskDraft(title: '原有任务'));
    await _pump(tester, database);
    await tester.longPress(find.text('原有任务'));
    await tester.pumpAndSettle();
    await repository.create(const TaskDraft(title: '新任务'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TasksPage)),
    );
    container.read(refreshProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('新任务'), findsOneWidget);
    expect(find.byTooltip('全选'), findsOneWidget);
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.byTooltip('取消全选'), findsOneWidget);
  });

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

  testWidgets('selection mode deletes multiple selected tasks', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    await repository.create(const TaskDraft(title: '待删除一'));
    await repository.create(const TaskDraft(title: '待删除二'));
    await repository.create(const TaskDraft(title: '保留任务'));
    await _pump(tester, database);

    expect(find.byTooltip('删除所选任务'), findsNothing);
    await tester.longPress(find.text('待删除一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待删除二'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('删除所选任务'), findsOneWidget);
    await tester.tap(find.byTooltip('删除所选任务'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 个任务？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect((await repository.list()).map((task) => task.title), ['保留任务']);
    expect(find.text('保留任务'), findsOneWidget);
  });

  testWidgets('postponing in a project leaves other project deadlines unchanged',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    for (final id in ['project-a', 'project-b']) {
      await database.into(database.projects).insert(
            ProjectsCompanion.insert(id: Value(id), name: id),
          );
    }
    final repository = TaskRepository(database);
    final now = DateTime.now();
    final oldDue = DateTime(now.year, now.month, now.day - 1, 18);
    final first = await repository.create(TaskDraft(
      title: '项目内逾期', projectId: 'project-a', dueAt: oldDue,
    ));
    final outside = await repository.create(TaskDraft(
      title: '其他项目逾期', projectId: 'project-b', dueAt: oldDue,
    ));
    await _pump(tester, database, projectId: 'project-a');
    await tester.tap(find.text('一键顺延到今天'));
    await tester.pumpAndSettle();

    expect((await repository.get(first.id)).dueAt,
        DateTime(now.year, now.month, now.day, 18).millisecondsSinceEpoch);
    expect((await repository.get(outside.id)).dueAt,
        oldDue.millisecondsSinceEpoch);
  });

  testWidgets('canceled tasks are excluded from the overdue action count',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    final now = DateTime.now();
    final oldDue = DateTime(now.year, now.month, now.day - 1, 18);
    await repository.create(TaskDraft(title: '未完成逾期', dueAt: oldDue));
    final canceled = await repository.create(
      TaskDraft(title: '已取消逾期', dueAt: oldDue),
    );
    await repository.setStatus(canceled.id, TaskStatus.canceled);
    await _pump(tester, database);

    expect(find.text('1 项任务已逾期'), findsOneWidget);
    await tester.tap(find.text('一键顺延到今天'));
    await tester.pumpAndSettle();
    expect((await repository.get(canceled.id)).dueAt,
        oldDue.millisecondsSinceEpoch);
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase database,
    {String? projectId}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: MaterialApp(home: TasksPage(projectId: projectId)),
  ));
  await tester.pumpAndSettle();
}
