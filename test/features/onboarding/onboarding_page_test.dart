import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/app/app.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch explains local workflow and can be skipped',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(shared),
      ],
      child: const LifeHubApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('先从今天开始'), findsOneWidget);
    expect(find.text('跳过引导'), findsOneWidget);
    await tester.tap(find.text('跳过引导'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(shared.getBool('lifehub.onboarding.completed'), isTrue);
  });

  testWidgets('completed onboarding opens the application shell',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lifehub.onboarding.completed': true,
    });
    final shared = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(shared),
      ],
      child: const LifeHubApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('先从今天开始'), findsNothing);
  });
}
