import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/credentials/data/credential_repository.dart';
import 'package:lifehub/features/credentials/presentation/credentials_page.dart';
import 'package:lifehub/features/evening/presentation/evening_plan_page.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/task/presentation/tasks_page.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/ui/responsive_test_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  AppDatabase database,
  Widget page, {
  Size size = const Size(390, 844),
  double scale = 1,
  double keyboard = 0,
}) async {
  await configurePhone(
    tester,
    ResponsiveTestCase(
      'form',
      size: size,
      textScale: scale,
      keyboardHeight: keyboard,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        theme: LifeHubTheme.light().copyWith(platform: TargetPlatform.android),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seedWeather(AppDatabase database) async {
  final now = DateTime.now();
  await database
      .into(database.weatherLocations)
      .insert(
        WeatherLocationsCompanion.insert(
          id: const Value('test-city'),
          name: '测试地区',
          latitude: 39,
          longitude: 116,
          isDefault: const Value(true),
        ),
      );
  for (var offset = 0; offset < 3; offset++) {
    final date = DateTime(now.year, now.month, now.day + offset);
    await database
        .into(database.weatherForecastCaches)
        .insert(
          WeatherForecastCachesCompanion.insert(
            locationId: 'test-city',
            forecastDate: DateKeys.toLocalDateKey(date),
            fetchedAt: now.millisecondsSinceEpoch,
            payloadJson: jsonEncode({
              'date': date.toIso8601String(),
              'weatherCode': offset == 0 ? 0 : 61,
              'minimumTemperature': offset == 0 ? 20 : 14,
              'maximumTemperature': offset == 0 ? 24 : 25,
              'precipitationProbability': offset == 0 ? 0 : 43,
            }),
          ),
        );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          if (call.method == 'initialize' ||
              call.method == 'areNotificationsEnabled' ||
              call.method == 'canScheduleExactNotifications') {
            return true;
          }
          if (call.method == 'pendingNotificationRequests' ||
              call.method == 'getActiveNotifications') {
            return <Map<String, dynamic>>[];
          }
          return null;
        });
    try {
      await NotificationService.instance.initialize();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
  });

  testWidgets('task form fits narrow phones with keyboard and saves choices', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(
      tester,
      database,
      const TasksPage(),
      size: const Size(320, 720),
      scale: 1.3,
      keyboard: 220,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expectNoLayoutFailure(tester);
    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(500));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('请输入任务标题'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '出行资料');
    final study = find.widgetWithText(ChoiceChip, '学习');
    await tester.ensureVisible(study);
    await tester.tap(study);
    final priority = find.widgetWithText(ChoiceChip, 'P1 紧急');
    await tester.ensureVisible(priority);
    await tester.tap(priority);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final task = (await TaskRepository(database).list()).single;
    expect(task.title, '出行资料');
    expect(task.category, TaskCategory.study);
    expect(task.priority, 1);
    expectNoLayoutFailure(tester);
  });

  testWidgets(
    'credential templates stay visible and blank names show feedback',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _pump(tester, database, const CredentialsPage());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入证件名称'), findsOneWidget);
      final template = find.widgetWithText(ChoiceChip, '社保卡');
      expect(template, findsOneWidget);
      final templateRect = tester.getRect(template);
      expect(templateRect.left, greaterThanOrEqualTo(0));
      expect(templateRect.right, lessThanOrEqualTo(390));
      await tester.tap(template);
      await tester.pumpAndSettle();
      expect(find.text('请输入证件名称'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(
        (await CredentialRepository(database).list()).single.name,
        '社会保障卡',
      );
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets('task time labels remain readable on narrow large-text forms', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(
      tester,
      database,
      const TasksPage(),
      size: const Size(320, 720),
      scale: 1.6,
      keyboard: 220,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '时段任务');
    await tester.ensureVisible(find.text('设置时间段'));
    await tester.tap(find.text('设置时间段'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始时间'));
    expect(tester.getSize(find.text('开始时间')).height, lessThan(36));
    expectNoLayoutFailure(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final task = (await TaskRepository(database).list()).single;
    expect(task.startAt, isNotNull);
    expect(
      task.dueAt! - task.startAt!,
      const Duration(hours: 1).inMilliseconds,
    );
  });

  testWidgets(
    'credential cards leave room for complete names and expiry dates',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await CredentialRepository(database).create(
        CredentialDraft(
          name: '阿里云服务器病毒查杀',
          expiryDate: DateTime(2026, 11, 12),
          numberHint: '尾号1234',
          holder: '小王',
        ),
      );
      await _pump(
        tester,
        database,
        const CredentialsPage(),
        size: const Size(320, 800),
        scale: 1.6,
      );
      expect(find.text('阿里云服务器病毒查杀'), findsOneWidget);
      final date = find.text('2026-11-12 到期');
      expect(date, findsOneWidget);
      expect(tester.getSize(date).height, lessThan(32));
      expect(find.text('持有人 小王'), findsOneWidget);
      expect(find.textContaining('尾号1234'), findsOneWidget);
      expectNoLayoutFailure(tester);
      await tester.tap(find.text('仅记录尾号，使用本机提醒'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请勿填写完整证件号码'), findsOneWidget);
    },
  );

  testWidgets('credential form remains usable with larger text and keyboard', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pump(
      tester,
      database,
      const CredentialsPage(),
      size: const Size(320, 720),
      scale: 1.6,
      keyboard: 220,
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expectNoLayoutFailure(tester);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, '保存')).bottom,
      lessThanOrEqualTo(500),
    );
  });

  testWidgets(
    'rain and access-card tips share a row and save to the selected day',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedWeather(database);
      await _pump(tester, database, const EveningPlanPage());
      final rain = find.textContaining('有雨');
      final pass = find.text('门禁卡 / 证件');
      expect(rain, findsOneWidget);
      expect(pass, findsOneWidget);
      final rainRect = tester.getRect(rain);
      final passRect = tester.getRect(pass);
      expect((rainRect.center.dy - passRect.center.dy).abs(), lessThan(5));
      expect(passRect.left, greaterThan(rainRect.right));
      await tester.tap(pass);
      await tester.pumpAndSettle();
      final item =
          (await database.select(database.eveningPrepItems).get()).single;
      final now = DateTime.now();
      expect(item.title, '门禁卡/证件');
      expect(
        item.localDate,
        DateKeys.toLocalDateKey(DateTime(now.year, now.month, now.day + 1)),
      );
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(find.textContaining('有雨'), findsNothing);
      expect(find.textContaining('温差大'), findsNothing);
      expectNoLayoutFailure(tester);
    },
  );

  testWidgets('evening tips wrap safely on small phones with large text', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedWeather(database);
    await _pump(
      tester,
      database,
      const EveningPlanPage(),
      size: const Size(320, 800),
      scale: 1.6,
    );
    expect(find.textContaining('有雨'), findsOneWidget);
    expect(find.text('门禁卡 / 证件'), findsOneWidget);
    expectNoLayoutFailure(tester);
  });
}
