import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('task card displays clean layout, more options sheet, and filter chips',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);

    await repository.create(const TaskDraft(
      title: '整理所有评选奖学金资料',
      priority: 1,
      category: TaskCategory.study,
    ));

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 检查卡片标题与 P1 徽章正常显示
    expect(find.text('整理所有评选奖学金资料'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
    expect(find.textContaining('学习'), findsOneWidget);

    // 点击更多操作按钮 (more_horiz) 呼出底部菜单
    expect(find.byTooltip('任务操作'), findsOneWidget);
    await tester.tap(find.byTooltip('任务操作'));
    await tester.pumpAndSettle();

    expect(find.text('修改任务'), findsOneWidget);
    expect(find.text('顺延到明天'), findsOneWidget);
    expect(find.text('关联关系'), findsOneWidget);
    expect(find.text('删除任务'), findsOneWidget);

    // 关闭菜单
    await tester.tap(find.text('修改任务'));
    await tester.pumpAndSettle();

    // 检查编辑弹窗中的 ChoiceChips
    expect(find.text('P1 紧急'), findsOneWidget);
    expect(find.text('P2 重要'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '学习'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 打开筛选弹窗
    await tester.tap(find.byTooltip('筛选任务'));
    await tester.pumpAndSettle();

    expect(find.text('筛选任务'), findsOneWidget);
    expect(find.text('全部分类'), findsOneWidget);
    expect(find.text('重置条件'), findsOneWidget);
    expect(find.text('应用筛选'), findsOneWidget);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
  });

  testWidgets('task card swipe right marks complete and swipe left postpones',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);

    final created = await repository.create(const TaskDraft(
      title: '右滑完成测试任务',
      priority: 2,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('右滑完成测试任务'), findsOneWidget);

    // Swipe right by 120 pixels to trigger completion
    await tester.drag(find.text('右滑完成测试任务'), const Offset(120, 0));
    await tester.pumpAndSettle();

    final tasks = await repository.list();
    expect(tasks.firstWhere((t) => t.id == created.id).status, TaskStatus.done);
  });

  testWidgets('done task card swipe right resets to todo and swipe left postpones',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);

    final created = await repository.create(const TaskDraft(
      title: '已完成任务待重置',
      priority: 1,
    ));
    await repository.setStatus(created.id, TaskStatus.done);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已完成任务待重置'), findsOneWidget);

    // Swipe right by 130 pixels to trigger reset
    await tester.drag(find.text('已完成任务待重置'), const Offset(130, 0));
    await tester.pumpAndSettle();

    final tasks = await repository.list();
    expect(tasks.firstWhere((t) => t.id == created.id).status, TaskStatus.todo);
  });

  testWidgets('task card swipe left postpones task to tomorrow',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);

    final created = await repository.create(const TaskDraft(
      title: '左滑顺延测试任务',
      priority: 3,
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('左滑顺延测试任务'), findsOneWidget);

    // Swipe left by 150 pixels to trigger postponing
    await tester.drag(find.text('左滑顺延测试任务'), const Offset(-150, 0));
    await tester.pumpAndSettle();

    final tasks = await repository.list();
    final updated = tasks.firstWhere((t) => t.id == created.id);
    expect(updated.dueAt, isNotNull);
  });
}
