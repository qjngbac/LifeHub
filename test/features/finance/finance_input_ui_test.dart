import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';
import 'package:lifehub/features/finance/presentation/finance_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, AppDatabase database) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: FinancePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'quick additions preserve cents and evaluate the entered expression',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _pump(tester, database);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final amount = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText?.startsWith('金额') ?? false),
      );
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '12.34');
      await tester.tap(find.text('+10'));
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller!.text, '22.34');
      await tester.enterText(amount, '25+15');
      await tester.tap(find.text('+10'));
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller!.text, '50.00');
      await tester.enterText(amount, '12.34');
      await tester.tap(find.text('+50'));
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller!.text, '62.34');
      await tester.enterText(amount, '0');
      await tester.tap(find.text('+10'));
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller!.text, '10.00');
      await tester.enterText(amount, '无效算式');
      await tester.tap(find.text('+10'));
      await tester.pump();
      expect(tester.widget<TextField>(amount).controller!.text, '无效算式');
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
    },
  );
  testWidgets('saving an unchanged decimal budget preserves its minor units', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await FinancePreferences(
      preferences,
    ).setMonthlyBudget(now.year, now.month, 123456);
    await _pump(tester, database);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设定月度支出预算'));
    await tester.pumpAndSettle();
    final amount = find.byType(TextField);
    expect(tester.widget<TextField>(amount).controller!.text, '1234.56');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(
      FinancePreferences(preferences).getMonthlyBudget(now.year, now.month),
      123456,
    );
  });
  testWidgets('loading failure offers a retry instead of spinning forever', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (_) => throw StateError('test database unavailable'),
      ),
    );
    addTearDown(database.close);
    await _pump(tester, database);
    expect(find.text('财务数据加载失败，请重试'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
  });
}
