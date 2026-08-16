import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/automation/application/automation_engine.dart';
import 'package:lifehub/features/automation/data/automation_repository.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  test('weekly rule creates once for one local date and records execution',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final rules = AutomationRepository(database);
    await rules.create(AutomationRuleDraft(
      name: '每周复盘',
      triggerType: 'WEEKLY',
      triggerJson: jsonEncode({'weekday': 7}),
      actionType: 'CREATE_TASK',
      actionJson: jsonEncode({'title': '完成本周复盘'}),
    ));
    final engine = AutomationEngine(database);
    final sunday = DateTime(2026, 8, 9, 9);

    expect(await engine.runDue(sunday), 1);
    expect(await engine.runDue(sunday.add(const Duration(hours: 1))), 0);
    expect((await TaskRepository(database).list()).single.title, '完成本周复盘');
    expect(await rules.runs(), hasLength(1));
  });

  test('course review template runs after the selected class end time',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await AutomationRepository(database).create(AutomationRuleDraft(
      name: '课程复习',
      triggerType: 'COURSE_REVIEW',
      triggerJson: jsonEncode({'weekday': 1, 'afterMinutes': 17 * 60}),
      actionType: 'CREATE_TASK',
      actionJson: jsonEncode({'title': '复习今天的课程'}),
    ));

    expect(
        await AutomationEngine(database).runDue(DateTime(2026, 8, 10, 16)), 0);
    expect(
        await AutomationEngine(database).runDue(DateTime(2026, 8, 10, 18)), 1);
    expect((await TaskRepository(database).list()).single.title, '复习今天的课程');
  });

  test('anniversary preparation rule uses the anniversary title', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final anniversary = await AnniversaryRepository(database).create(
      AnniversaryDraft(title: '相识纪念日', date: DateTime(2020, 8, 20)),
    );
    await AutomationRepository(database).create(AutomationRuleDraft(
      name: '纪念日前准备',
      triggerType: 'ANNIVERSARY_BEFORE',
      triggerJson:
          jsonEncode({'anniversaryId': anniversary.id, 'daysBefore': 3}),
      actionType: 'CREATE_TASK',
      actionJson: jsonEncode({'title': '准备{anniversary}'}),
    ));

    expect(
        await AutomationEngine(database).runDue(DateTime(2026, 8, 17, 9)), 1);
    expect((await TaskRepository(database).list()).single.title, '准备相识纪念日');
  });

  test('rollover moves overdue unfinished tasks to today', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final tasks = TaskRepository(database);
    await tasks.create(TaskDraft(
      title: '昨天没做完',
      dueAt: DateTime(2026, 8, 8, 18),
    ));
    await AutomationRepository(database).create(const AutomationRuleDraft(
      name: '未完成任务顺延',
      triggerType: 'DAILY',
      triggerJson: '{}',
      actionType: 'ROLLOVER_TASKS',
      actionJson: '{}',
    ));

    expect(await AutomationEngine(database).runDue(DateTime(2026, 8, 9, 8)), 1);
    final task = (await tasks.list()).single;
    final due =
        DateTime.fromMillisecondsSinceEpoch(task.dueAt!, isUtc: true).toLocal();
    expect((due.year, due.month, due.day), (2026, 8, 9));
  });
}
