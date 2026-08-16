import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/data_hub/presentation/data_hub_page.dart';
import 'package:lifehub/features/calendar/presentation/calendar_page.dart';
import 'package:lifehub/features/course/presentation/courses_page.dart';
import 'package:lifehub/features/settings/presentation/my_page.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../shared/ui/responsive_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('zh_CN'));

  for (final testCase in phoneAccessibilityMatrix) {
    testWidgets('data hub fits ${testCase.name}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await configurePhone(tester, testCase);
      await tester.pumpWidget(const MaterialApp(home: DataHubPage()));
      await tester.pumpAndSettle();
      expect(find.text('数据'), findsOneWidget);
      expectNoLayoutFailure(tester);
    });

    testWidgets('task empty state fits ${testCase.name}', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await configurePhone(tester, testCase);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: TasksPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('还没有任务'), findsOneWidget);
      expectNoLayoutFailure(tester);
    });
  }

  testWidgets('keyboard-safe dialog remains actionable on compact large text',
      (tester) async {
    await configurePhone(
      tester,
      const ResponsiveTestCase(
        'compact-keyboard',
        size: Size(320, 568),
        textScale: 2,
        keyboardHeight: 260,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => KeyboardSafeFormDialog(
                title: const Text('新建任务'),
                body: Column(children: [
                  for (var index = 0; index < 8; index++)
                    TextField(
                      decoration: InputDecoration(labelText: '字段 $index'),
                    ),
                ]),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('取消')),
                  FilledButton(onPressed: () {}, child: const Text('保存')),
                ],
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.getBottomRight(find.text('保存')).dy, lessThan(308));
    expectNoLayoutFailure(tester);
  });

  for (final page in <(String, Widget)>[
    ('calendar', const CalendarPage()),
    ('courses', const CoursesPage()),
    ('settings', const MyPage()),
  ]) {
    testWidgets('${page.$1} fits compact accessibility mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await configurePhone(
        tester,
        const ResponsiveTestCase(
          'compact-accessibility',
          size: Size(320, 568),
          textScale: 2,
        ),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(home: page.$2),
      ));
      await tester.pumpAndSettle();
      expectNoLayoutFailure(tester);
    });
  }
}
