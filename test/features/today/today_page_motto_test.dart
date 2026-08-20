import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/today/presentation/today_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('homepage motto is created once and edited by tapping its text',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const MaterialApp(home: TodayPage()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byTooltip('添加首页标语'), findsOneWidget);
    await tester.tap(find.byTooltip('添加首页标语'));
    await tester.pumpAndSettle();
    expect(find.text('设置首页标语'), findsOneWidget);

    const longMotto = '今天也要稳稳向前，把每一个小步骤都做扎实，累积会让遥远的目标慢慢变成眼前的风景；'
        '路很长，也要记得照顾自己，保持耐心，然后继续完成下一件重要的小事。';
    await tester.enterText(find.byType(TextField), longMotto);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(longMotto), findsOneWidget);
    expect(find.byTooltip('添加首页标语'), findsNothing);

    final mottoFinder = find.byKey(const Key('today_motto'));
    final mottoRect = tester.getRect(mottoFinder);
    final customizeRect = tester.getRect(find.byTooltip('自定义今天'));
    expect(
      (mottoRect.center.dy - customizeRect.center.dy).abs(),
      lessThan(12),
      reason: '标语应当与顶部自定义按钮处于同一行，而不是另占一行',
    );
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final mottoText = tester.widget<Text>(find.text(longMotto));
    expect(mottoText.style?.color, theme.colorScheme.onSurface);
    expect(mottoText.softWrap, isFalse);
    expect(mottoText.overflow, TextOverflow.visible);
    expect(
      tester.getSize(find.text(longMotto)).width,
      greaterThan(mottoRect.width),
      reason: '滚动子项必须按完整文本宽度布局，不能先被顶部可见宽度截断',
    );
    final mottoMaterials = tester.widgetList<Material>(
      find.ancestor(of: mottoFinder, matching: find.byType(Material)),
    );
    expect(
      mottoMaterials.any(
        (material) => material.color == theme.colorScheme.secondaryContainer,
      ),
      isFalse,
      reason: '标语应沿用顶部背景，不应再有单独的紫色底色',
    );

    await tester.tap(mottoFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('编辑首页标语'), findsOneWidget);
  });
}
