import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/weather/data/weather_repository.dart';
import 'package:lifehub/features/weather/presentation/weather_locations_page.dart';

void main() {
  testWidgets('displays empty state when no weather locations are present',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeatherLocationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂未添加天气地区'), findsOneWidget);
    expect(find.text('定位当前城市'), findsOneWidget);
    expect(find.text('手动搜索地区'), findsOneWidget);
  });

  testWidgets(
      'displays hero weather card and location management list when locations exist',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = WeatherRepository(database);

    await repository.saveLocation(
      const WeatherLocationDraft(
        name: '呈贡区',
        country: '中国',
        admin1: '云南省',
        admin2: '昆明市',
        latitude: 24.8893,
        longitude: 102.8014,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: true,
    );

    await repository.saveLocation(
      const WeatherLocationDraft(
        name: '柘城县',
        country: '中国',
        admin1: '河南省',
        admin2: '商丘市',
        latitude: 34.0911,
        longitude: 115.3054,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeatherLocationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Hero Card displays primary city
    expect(find.text('当前主城'), findsWidgets);
    expect(find.text('呈贡区'), findsWidgets);
    expect(find.text('柘城县'), findsOneWidget);
    expect(find.text('地区管理 (2)'), findsOneWidget);
    expect(find.text('设为主城'), findsOneWidget);
  });

  testWidgets('opens search dialog and shows hot chips and instant search',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeatherLocationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加备用地区'));
    await tester.pumpAndSettle();

    expect(find.text('搜索备用地区'), findsOneWidget);
    expect(find.text('柘城'), findsOneWidget);
    expect(find.text('呈贡'), findsOneWidget);

    // Enter 柘城 in textfield
    await tester.enterText(find.byType(TextField), '柘城');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('柘城县'), findsOneWidget);
    expect(find.textContaining('商丘市'), findsOneWidget);
  });

  test('formatLocationHierarchy formats concise administrative divisions', () {
    const entry1 = WeatherLocationEntry(
      id: '1',
      name: '呈贡区',
      country: '中国',
      admin1: '云南省',
      admin2: '昆明市',
      latitude: 24.88,
      longitude: 102.80,
      timezone: 'Asia/Shanghai',
      isDefault: true,
      isFavorite: true,
      sortKey: 1,
      syncState: 0,
      metadata: '{}',
      createdAt: 1,
      updatedAt: 1,
      version: 1,
    );
    expect(formatLocationHierarchy(entry1), '云南省 · 昆明市');

    const entry2 = WeatherLocationEntry(
      id: '2',
      name: '柘城县',
      country: '中国',
      admin1: '河南省',
      admin2: '商丘市',
      latitude: 34.09,
      longitude: 115.30,
      timezone: 'Asia/Shanghai',
      isDefault: false,
      isFavorite: true,
      sortKey: 2,
      syncState: 0,
      metadata: '{}',
      createdAt: 1,
      updatedAt: 1,
      version: 1,
    );
    expect(formatLocationHierarchy(entry2), '河南省 · 商丘市');

    const entryDirect = WeatherLocationEntry(
      id: '3',
      name: '海淀区',
      country: '中国',
      admin1: '北京',
      admin2: '北京市',
      latitude: 39.96,
      longitude: 116.30,
      timezone: 'Asia/Shanghai',
      isDefault: false,
      isFavorite: true,
      sortKey: 3,
      syncState: 0,
      metadata: '{}',
      createdAt: 1,
      updatedAt: 1,
      version: 1,
    );
    expect(formatLocationHierarchy(entryDirect), '北京市');
  });

  testWidgets(
      'tapping non-default location tile opens weather dialog instead of directly switching',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = WeatherRepository(database);

    await repository.saveLocation(
      const WeatherLocationDraft(
        name: '呈贡区',
        country: '中国',
        admin1: '云南省',
        admin2: '昆明市',
        latitude: 24.8893,
        longitude: 102.8014,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: true,
    );

    final zhecheng = await repository.saveLocation(
      const WeatherLocationDraft(
        name: '柘城县',
        country: '中国',
        admin1: '河南省',
        admin2: '商丘市',
        latitude: 34.0911,
        longitude: 115.3054,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeatherLocationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial default is 呈贡区
    final defaultBefore = await repository.defaultLocation();
    expect(defaultBefore?.name, '呈贡区');

    // Tap on 柘城县 tile (find by InkWell containing 柘城县)
    final zhechengTextFinder = find.text('柘城县');
    expect(zhechengTextFinder, findsOneWidget);
    await tester.tap(zhechengTextFinder);
    await tester.pumpAndSettle();

    // Dialog should be displayed showing 柘城县 weather preview
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('备用地区'), findsOneWidget);

    // Default location in repository should still NOT have changed yet!
    final defaultAfterTap = await repository.defaultLocation();
    expect(defaultAfterTap?.name, '呈贡区');

    // Tap "设为主城" inside the dialog
    final setInDialog = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('设为主城'),
    );
    expect(setInDialog, findsOneWidget);
    await tester.tap(setInDialog);
    await tester.pumpAndSettle();

    // Now default location is changed to 柘城县
    final defaultAfterDialog = await repository.defaultLocation();
    expect(defaultAfterDialog?.id, zhecheng.id);
  });

  testWidgets(
      'long-pressing non-default location prompts for deletion and deletes it',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = WeatherRepository(database);

    await repository.saveLocation(
      const WeatherLocationDraft(
        name: '呈贡区',
        country: '中国',
        admin1: '云南省',
        admin2: '昆明市',
        latitude: 24.8893,
        longitude: 102.8014,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: true,
    );

    await repository.saveLocation(
      const WeatherLocationDraft(
        name: '柘城县',
        country: '中国',
        admin1: '河南省',
        admin2: '商丘市',
        latitude: 34.0911,
        longitude: 115.3054,
        timezone: 'Asia/Shanghai',
      ),
      makeDefault: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: WeatherLocationsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Long press 柘城县
    await tester.longPress(find.text('柘城县'));
    await tester.pumpAndSettle();

    // Dialog asking for deletion confirmation
    expect(find.text('删除地区'), findsOneWidget);
    expect(find.textContaining('确定要删除备用地区「柘城县」吗？'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 柘城县 should no longer exist in the list
    expect(find.text('柘城县'), findsNothing);
    final remaining = await repository.locations();
    expect(remaining.length, 1);
    expect(remaining.single.name, '呈贡区');
  });
}
