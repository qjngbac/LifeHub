import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/presentation/anniversaries_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('anniversaries page shows empty state when no items', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: AnniversariesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('记录生日、考研、纪念日和重要节点'), findsOneWidget);
    expect(find.text('添加第一个纪念日'), findsOneWidget);
  });

  testWidgets('anniversaries page displays Hero banner, number blocks and actions',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final repo = AnniversaryRepository(database);
    final now = DateTime.now();

    // 添加考研（未来倒数）
    await repo.create(AnniversaryDraft(
      title: '考研初试',
      date: now.add(const Duration(days: 74)),
      category: 'EXAM',
      repeatYearly: false,
    ));

    // 添加恋爱纪念（过去累计）
    await repo.create(AnniversaryDraft(
      title: '在一起相识',
      date: now.subtract(const Duration(days: 520)),
      category: 'RELATIONSHIP',
      repeatYearly: false,
    ));

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: AnniversariesPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 检查 Hero 看板展示最近即将到来的考研
    expect(find.textContaining('考研初试'), findsAtLeastNWidgets(1));
    expect(find.text('焦点倒数'), findsOneWidget);
    expect(find.text('学业'), findsOneWidget);

    // 检查列表展示项
    expect(find.textContaining('在一起相识'), findsOneWidget);
    expect(find.text('74'), findsWidgets);
    expect(find.text('520'), findsOneWidget);

    // 长按卡片弹出操作 BottomSheet
    final itemToLongPress = find.text('在一起相识');
    await tester.longPress(itemToLongPress);
    await tester.pumpAndSettle();

    expect(find.text('设为顶部看板置顶'), findsOneWidget);
    expect(find.text('修改事件'), findsOneWidget);
    expect(find.text('删除事件'), findsOneWidget);

    // 点击置顶
    await tester.tap(find.text('设为顶部看板置顶'));
    await tester.pumpAndSettle();

    // 此时 Hero 看板变为置顶恋爱纪念
    expect(find.text('置顶看板'), findsOneWidget);
    expect(find.textContaining('在一起相识 已经'), findsOneWidget);
  });

  testWidgets(
      'anniversaries page displays lunar anniversary with badge and lunar date',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final repo = AnniversaryRepository(database);
    final now = DateTime.now();

    await repo.create(AnniversaryDraft(
      title: '中秋节吃月饼',
      date: now.add(const Duration(days: 30)),
      category: 'HOLIDAY',
      repeatYearly: true,
      isLunar: true,
      lunarMonth: 8,
      lunarDay: 15,
    ));

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: AnniversariesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('中秋节吃月饼'), findsAtLeastNWidgets(1));
    expect(find.text('农历'), findsWidgets);
    expect(find.textContaining('农历 八月十五'), findsWidgets);
  });

  testWidgets('tapping add navigates to AnniversaryFormPage with zero checkmark chips', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: AnniversariesPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 点击添加
    await tester.tap(find.text('添加第一个纪念日'));
    await tester.pumpAndSettle();

    // 验证打开独立页面
    expect(find.text('添加纪念日 / 倒数日'), findsOneWidget);

    // 验证分类 ChoiceChip 的 showCheckmark 均为 false
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(chips, isNotEmpty);
    for (final chip in chips) {
      expect(chip.showCheckmark, isFalse, reason: '选中生活等分类时去除对勾与圆形阴影');
    }

    // 切换到农历历法
    await tester.tap(find.text('农历 (阴历)'));
    await tester.pumpAndSettle();

    // 验证农历年份独占一行（有农历年份标签），月份与日期均有独立标签
    expect(find.text('农历年份'), findsOneWidget);
    expect(find.text('农历月份'), findsOneWidget);
    expect(find.text('农历日期'), findsOneWidget);

    // 输入名称并保存
    await tester.enterText(find.byType(TextFormField).first, '全能离线纪念');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 页面退回主列表并展示新添加的纪念日
    expect(find.text('全能离线纪念'), findsWidgets);
  });
}
