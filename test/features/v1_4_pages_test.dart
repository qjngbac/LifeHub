import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/automation/presentation/automation_page.dart';
import 'package:lifehub/features/calendar/presentation/calendar_exchange_page.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/inbox/presentation/inbox_page.dart';

void main() {
  testWidgets('inbox page shows a capture and conversion action',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await InboxRepository(database).capture('保存的文字');
    await tester.pumpWidget(_app(database, const InboxPage()));
    await tester.pumpAndSettle();
    expect(find.text('收件箱'), findsOneWidget);
    expect(find.text('保存的文字'), findsOneWidget);
    expect(find.text('整理'), findsOneWidget);
  });

  testWidgets('automation page describes bounded local rules', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const AutomationPage()));
    await tester.pumpAndSettle();
    expect(find.text('本地自动化'), findsOneWidget);
    expect(find.text('还没有自动化规则'), findsOneWidget);
  });

  testWidgets('calendar exchange page is preview first', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(_app(database, const CalendarExchangePage()));
    await tester.pumpAndSettle();
    expect(find.text('日历导入导出'), findsOneWidget);
    expect(find.textContaining('预览'), findsWidgets);
  });
}

Widget _app(AppDatabase database, Widget page) => ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: page),
    );
