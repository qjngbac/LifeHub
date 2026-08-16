import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/archive/presentation/archive_page.dart';
import 'package:lifehub/features/data_health/presentation/data_health_page.dart';
import 'package:lifehub/features/reminder/presentation/reminder_center_page.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  testWidgets('reminder center shows the entity title', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '准备考试'));
    await database.into(database.reminders).insert(RemindersCompanion.insert(
          entityType: 'TASK',
          entityId: task.id,
          triggerAt: DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          notificationId: 800,
        ));

    await tester.pumpWidget(_app(database, const ReminderCenterPage()));
    await tester.pumpAndSettle();

    expect(find.text('提醒中心'), findsOneWidget);
    expect(find.text('准备考试'), findsOneWidget);
  });

  testWidgets('data health page reports an empty database as healthy',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const DataHealthPage()));
    await tester.pumpAndSettle();
    expect(find.text('数据健康'), findsOneWidget);
    expect(find.text('没有发现数据问题'), findsOneWidget);
  });

  testWidgets('archive page separates archived and recently deleted items',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final task =
        await TaskRepository(database).create(const TaskDraft(title: '删除项'));
    await TaskRepository(database).delete(task.id);

    await tester.pumpWidget(_app(database, const ArchivePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除项'), findsOneWidget);
    expect(find.text('永久删除'), findsOneWidget);
  });
}

Widget _app(AppDatabase database, Widget child) => ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: child),
    );
