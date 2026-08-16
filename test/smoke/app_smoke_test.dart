import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/app/app.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';

void main() {
  testWidgets('app renders the five-entry navigation shell', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const LifeHubApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('日程'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
  });

  testWidgets('middle navigation action opens quick create', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const LifeHubApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    expect(find.text('快速创建'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsWidgets);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('快速创建'), findsOneWidget);

    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(find.text('快速创建'), findsNothing);
  });

  testWidgets('key shell remains usable with large system text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const LifeHubApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.storage_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('急救知识'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('急救知识'), findsOneWidget);
  });
}
