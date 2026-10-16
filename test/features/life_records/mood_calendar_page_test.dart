import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/life_records/presentation/mood_calendar_page.dart';
import 'package:lifehub/features/life_records/presentation/life_month_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('historical quick logging labels and saves the selected date',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MoodCalendarPage()),
    ));
    await tester.pumpAndSettle();
    tester.widget<LifeMonthCalendar>(find.byType(LifeMonthCalendar))
        .onSelected(DateTime(2020, 1, 2));
    await tester.pumpAndSettle();
    expect(find.text('今日心情极速速记'), findsNothing);
    expect(find.text('当天心情极速速记'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-mood-HAPPY')));
    await tester.pumpAndSettle();
    expect((await MoodRepository(database).forDate(DateTime(2020, 1, 2)))!
        .moodCode, MoodCatalog.happy);
    expect(await MoodRepository(database).forDate(DateTime.now()), isNull);
  });

  testWidgets('quick mood logging records mood on tap and updates the page',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MoodCalendarPage()),
    ));
    await tester.pumpAndSettle();

    // Verify quick mood logging card is displayed when today has no mood
    expect(find.text('今日心情极速速记'), findsOneWidget);
    expect(find.text('开心'), findsOneWidget);
    expect(find.text('平静'), findsOneWidget);
    expect(find.text('疲惫'), findsOneWidget);
    expect(find.text('低落'), findsOneWidget);
    expect(find.text('烦躁'), findsOneWidget);

    // Tap on the '开心' quick emoji
    await tester.tap(find.byKey(const ValueKey('quick-mood-HAPPY')));
    await tester.pumpAndSettle();

    // Verify snackbar is shown
    expect(find.text('已记录为 😊 开心，点击可修改'), findsOneWidget);

    // Verify the card changed from quick log to recorded state
    expect(find.text('今日心情极速速记'), findsNothing);
    expect(find.text('开心 · 强度 3/5'), findsOneWidget);

    // Verify in database
    final now = DateTime.now();
    final entry = await MoodRepository(database).forDate(now);
    expect(entry, isNotNull);
    expect(entry!.moodCode, MoodCatalog.happy);
    expect(entry.intensity, 3);
    expect(entry.localDate, DateKeys.toLocalDateKey(now));
  });

  testWidgets('tapping tired quick emoji logs TIRED mood properly',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MoodCalendarPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-mood-TIRED')));
    await tester.pumpAndSettle();

    expect(find.text('疲惫 · 强度 3/5'), findsOneWidget);
    final now = DateTime.now();
    final entry = await MoodRepository(database).forDate(now);
    expect(entry, isNotNull);
    expect(entry!.moodCode, MoodCatalog.tired);
  });

  testWidgets('horizontal swiping on calendar switches month',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MoodCalendarPage()),
    ));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final currentMonthTitle = '${now.year}年${now.month}月';
    expect(find.text(currentMonthTitle), findsOneWidget);

    // Swipe left -> should navigate to next month
    await tester.fling(find.byType(LifeMonthCalendar), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    final nextMonth = DateTime(now.year, now.month + 1);
    final nextMonthTitle = '${nextMonth.year}年${nextMonth.month}月';
    expect(find.text(nextMonthTitle), findsOneWidget);

    // Swipe right -> should navigate back to current month
    await tester.fling(find.byType(LifeMonthCalendar), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text(currentMonthTitle), findsOneWidget);
  });
}

