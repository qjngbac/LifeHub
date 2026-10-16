import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/household/presentation/household_page.dart';

/// 家庭物品模块的表单与列表回归：
/// 1. 名称留空点保存必须给出明确提示（此前是 `if (title.isEmpty) return;`，毫无反馈）；
/// 2. 正常填写可以成功落库并出现在列表里；
/// 3. 品牌为空时不能出现"保修已到期 · "这种末尾悬空的分隔符。
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: HouseholdPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('名称留空时保存会给出提示，而不是毫无反应', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('物品'));
    await tester.pumpAndSettle();
    expect(find.text('添加家庭物品'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(
      find.text('请输入物品名称'),
      findsOneWidget,
      reason: '此前点保存毫无反馈，用户会以为按钮坏了',
    );
    expect(
      find.text('添加家庭物品'),
      findsOneWidget,
      reason: '校验失败时不应该关闭弹窗',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('填好名称后可以成功添加并出现在列表里', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('物品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '空气炸锅');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('添加家庭物品'), findsNothing);
    expect(find.text('空气炸锅'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没填品牌时不出现末尾悬空的“·”', (tester) async {
    await database.into(database.householdItems).insert(
      HouseholdItemsCompanion.insert(
        name: '老冰箱',
        warrantyEndDate: Value(DateKeys.toLocalDateKey(DateTime(2020, 1, 1))),
      ),
    );
    await pumpPage(tester);

    expect(
      find.text('保修至 2020-01-01'),
      findsOneWidget,
      reason: '旧写法是"保修已到期 · "加空品牌，末尾会剩一个孤零零的分隔点',
    );
    expect(find.text('老冰箱'), findsOneWidget);
    expect(find.text('保修已到期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
