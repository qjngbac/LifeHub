import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';

import '../../shared/ui/responsive_test_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  AppDatabase database, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
}) async {
  await configurePhone(
    tester,
    ResponsiveTestCase('task-list', size: size, textScale: scale),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        theme: dark ? LifeHubTheme.dark() : LifeHubTheme.light(),
        home: const TasksPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DateTime _tomorrow(int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, hour, minute);
}

String _date(DateTime date) => '${date.month}月${date.day}日';

void main() {
  testWidgets('swipe backgrounds follow group corners in both directions', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    final root = await repository.create(const TaskDraft(title: '组首'));
    await repository.create(TaskDraft(title: '组中', parentTaskId: root.id));
    await repository.create(TaskDraft(title: '组尾', parentTaskId: root.id));
    await repository.create(const TaskDraft(title: '独立任务'));
    await _pump(tester, database);

    for (final title in ['组首', '组中', '组尾', '独立任务']) {
      final card = tester.widget<Card>(
        find.ancestor(of: find.text(title), matching: find.byType(Card)).first,
      );
      final radius = (card.shape! as RoundedRectangleBorder).borderRadius;
      for (final direction in [1, -1]) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.text(title)),
        );
        await gesture.moveBy(Offset(direction * 25, 0));
        await tester.pump();
        await gesture.moveBy(Offset(direction * 55, 0));
        await tester.pump();
        final background = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  (direction == 1
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF97316)),
        );
        expect(background, findsOneWidget);
        expect(
          (tester.widget<Container>(background).decoration! as BoxDecoration)
              .borderRadius,
          radius,
        );
        await gesture.cancel();
        await tester.pumpAndSettle();
      }
    }
    expectNoLayoutFailure(tester);
  });

  testWidgets('deep subtasks keep card width and show complete due dates', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    final titles = ['奖学金资料', '证书上传', '整理证书编号', '学习证书规范', '证书收集'];
    String? parent;
    for (var depth = 0; depth < titles.length; depth++) {
      final task = await repository.create(
        TaskDraft(
          title: titles[depth],
          parentTaskId: parent,
          category: TaskCategory.work,
          dueAt: _tomorrow(depth == 4 ? 15 : 23, depth == 4 ? 30 : 59),
        ),
      );
      parent = task.id;
    }
    await repository.setStatus(parent!, TaskStatus.done);
    await _pump(tester, database);

    final rootCard = find
        .ancestor(of: find.text(titles.first), matching: find.byType(Card))
        .first;
    final childCard = find
        .ancestor(of: find.text(titles.last), matching: find.byType(Card))
        .first;
    expect(tester.getSize(childCard).width, tester.getSize(rootCard).width);
    expect(tester.getSize(childCard).height, lessThan(90));
    expect(find.text('已完成'), findsNothing);
    expect(find.textContaining('23:59'), findsNothing);
    final due = find.text('${_date(_tomorrow(15, 30))} 15:30');
    expect(due, findsOneWidget);
    final dateParagraph = tester.renderObject<RenderParagraph>(due);
    expect(dateParagraph.didExceedMaxLines, isFalse);
    expectNoLayoutFailure(tester);
  });

  testWidgets('long titles expand separately while tapping still edits', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    const title = '整理所有评选奖学金材料并核对证书编号与上传要求，确认每项资料完整';
    await TaskRepository(database).create(const TaskDraft(title: title));
    await _pump(tester, database, size: const Size(320, 800), scale: 1.6);

    expect(find.byTooltip('展开任务标题'), findsOneWidget);
    await tester.tap(find.byTooltip('展开任务标题'));
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(find.byType(TextField), findsNothing);
    expectNoLayoutFailure(tester);

    await tester.tap(find.byTooltip('收起任务标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.text('编辑任务'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await TaskRepository(database).list()).single.title, title);
  });

  testWidgets('small large-text lists retain cross-day and cross-year times', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(database);
    final start = _tomorrow(23);
    final end = DateTime(start.year, start.month, start.day + 1, 1);
    final nextYear = DateTime(DateTime.now().year + 1, 2, 3, 9, 30);
    await repository.create(
      TaskDraft(title: '跨日任务', startAt: start, dueAt: end, priority: 1),
    );
    await repository.create(TaskDraft(title: '跨年任务', dueAt: nextYear));
    await _pump(
      tester,
      database,
      size: const Size(320, 800),
      scale: 2,
      dark: true,
    );

    final range = find.text('${_date(start)} 23:00–${_date(end)} 01:00');
    expect(range, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(range).didExceedMaxLines,
      isFalse,
    );
    expect(find.text('${nextYear.year}/2/3 09:30'), findsOneWidget);
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'subtask checkbox completes only that task and preserves grouping',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = TaskRepository(database);
      final root = await repository.create(const TaskDraft(title: '父任务'));
      final child = await repository.create(
        TaskDraft(
          title: '子任务',
          parentTaskId: root.id,
          dueAt: _tomorrow(23, 59),
        ),
      );
      await _pump(tester, database);
      final childCard = find
          .ancestor(of: find.text('子任务'), matching: find.byType(Card))
          .first;
      await tester.tap(
        find.descendant(of: childCard, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect((await repository.get(child.id)).status, TaskStatus.done);
      expect((await repository.get(root.id)).status, TaskStatus.todo);
      expect((await repository.get(child.id)).parentTaskId, root.id);
      expect(find.text(_date(_tomorrow(23, 59))), findsOneWidget);

      await tester.longPress(find.text('子任务'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await tester.tap(find.text('父任务'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 2 项'), findsOneWidget);
      expectNoLayoutFailure(tester);
    },
  );
}
