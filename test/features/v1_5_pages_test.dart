import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/library/presentation/library_page.dart';
import 'package:lifehub/features/location/presentation/locations_page.dart';
import 'package:lifehub/features/trip/presentation/trips_page.dart';

void main() {
  testWidgets('资料库页支持收藏和搜索', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: LibraryPage()),
    ));
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('添加便签'), findsOneWidget);
  });

  testWidgets('地点页说明不需要定位权限', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: LocationsPage()),
    ));
    expect(find.text('地点'), findsOneWidget);
    expect(find.textContaining('无需定位权限'), findsOneWidget);
  });

  testWidgets('旅行页提供状态筛选和创建入口', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: TripsPage()),
    ));
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('计划中'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('创建旅行'), findsOneWidget);
  });
}
