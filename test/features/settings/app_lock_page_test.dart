import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/features/settings/presentation/app_lock_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'setting the first PIN updates configured state and locks correctly',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(appLockProvider.notifier);
      expect(container.read(appLockProvider).configured, isFalse);
      await notifier.setPin('2468');
      expect(container.read(appLockServiceProvider).isConfigured, isTrue);
      expect(container.read(appLockProvider).configured, isTrue);
      expect(container.read(appLockProvider).isUnlocked, isTrue);
      notifier.lock();
      expect(container.read(appLockProvider).configured, isTrue);
      expect(container.read(appLockProvider).isUnlocked, isFalse);
      expect(await notifier.verify('wrong'), isFalse);
      expect(container.read(appLockProvider).isUnlocked, isFalse);
      expect(await notifier.verify('2468'), isTrue);
      await notifier.clearPin();
      expect(container.read(appLockProvider).configured, isFalse);
      expect(container.read(appLockProvider).isUnlocked, isFalse);
    },
  );

  testWidgets(
    'confirming a new PIN immediately shows enabled on the settings page',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const MaterialApp(home: AppLockPage()),
        ),
      );
      expect(find.text('未开启'), findsOneWidget);
      await tester.tap(find.text('开启二级密码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2468');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(find.text('再输入一次确认'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '2468');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('已开启'));
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('立即锁定'), findsOneWidget);
      expect(find.text('关闭二级密码'), findsOneWidget);
      expect(find.text('未开启'), findsNothing);
      await tester.tap(find.text('立即锁定'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppLockPage)),
      );
      expect(container.read(appLockProvider).configured, isTrue);
      expect(container.read(appLockProvider).isUnlocked, isFalse);
      // 清掉前面开启、锁定操作的提示，避免它们排队遮住这次校验反馈。
      ScaffoldMessenger.of(
        tester.element(find.byType(AppLockPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭二级密码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'wrong',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('二级密码不正确'));
      expect(find.text('二级密码不正确'), findsOneWidget);
      expect(find.text('已开启'), findsOneWidget);
      await tester.tap(find.text('关闭二级密码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2468');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      await _waitFor(tester, find.text('未开启'));
      expect(find.text('未开启'), findsOneWidget);
      expect(container.read(appLockServiceProvider).isConfigured, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
