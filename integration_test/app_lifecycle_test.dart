import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifehub/app/app.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 200,
}) async {
  for (var frame = 0; frame < maxFrames; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for the expected widget.');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigation remains usable after pause and resume',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('lifehub.onboarding.completed', true);
    final database = AppDatabase();
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const LifeHubApp(),
    ));
    await _pumpUntilVisible(tester, find.byType(NavigationBar));
    expect(find.byType(NavigationBar), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntilVisible(tester, find.byType(NavigationBar));

    await tester.tap(find.text('数据').last);
    await _pumpUntilVisible(tester, find.byTooltip('全局搜索'));
    expect(find.text('数据'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
