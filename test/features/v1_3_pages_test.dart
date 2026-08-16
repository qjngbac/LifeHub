import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/focus/presentation/focus_page.dart';
import 'package:lifehub/features/goal/presentation/goals_page.dart';
import 'package:lifehub/features/review/presentation/reviews_page.dart';

void main() {
  testWidgets('goal page offers creation and an honest empty state',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const GoalsPage()));
    await tester.pumpAndSettle();
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('还没有目标'), findsOneWidget);
    await tester.tap(find.byTooltip('新建目标'));
    await tester.pumpAndSettle();
    expect(find.text('创建目标'), findsOneWidget);
  });

  testWidgets('focus page exposes presets and starts one session',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const FocusPage()));
    await tester.pumpAndSettle();
    expect(find.text('专注与计时'), findsOneWidget);
    expect(find.text('专注倒计时'), findsOneWidget);
    expect(find.text('正向计时'), findsOneWidget);
    expect(find.text('45 分钟'), findsOneWidget);
    await tester.tap(find.text('开始专注'));
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsOneWidget);
  });

  testWidgets('focus page starts and restores a stopwatch session',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const FocusPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('正向计时'));
    await tester.pumpAndSettle();
    expect(find.text('从 00:00 开始计时'), findsOneWidget);
    expect(find.text('开始计时'), findsOneWidget);
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();

    expect(find.textContaining('正向计时·已经过'), findsOneWidget);
    final active = await database.select(database.focusSessions).getSingle();
    expect(active.mode, 'STOPWATCH');
    expect(active.plannedMinutes, 0);
  });

  testWidgets('review page displays local weekly summary', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const ReviewsPage()));
    await tester.pumpAndSettle();
    expect(find.text('复盘'), findsOneWidget);
    expect(find.text('周复盘'), findsOneWidget);
    expect(find.text('完成任务'), findsOneWidget);
    expect(find.byTooltip('历史复盘'), findsOneWidget);
  });
}

Widget _app(AppDatabase database, Widget page) => ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: page),
    );
