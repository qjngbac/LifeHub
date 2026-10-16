import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/focus/application/focus_controller.dart';
import 'package:lifehub/features/focus/application/white_noise_service.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';
import 'package:lifehub/features/focus/presentation/focus_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/white_noise');
  const notificationChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (_) async => true);
  });

  tearDown(() async {
    await WhiteNoiseService.instance.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
  });

  testWidgets('fullscreen resume updates controller and completes at deadline',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = FocusRepository(database);
    final started = DateTime.now().toUtc();
    final session = await repository.start(
      const FocusDraft(plannedMinutes: 1),
      now: started,
    );
    await repository.pause(session.id, now: started);
    var completions = 0;
    final controller = FocusController(
      repository,
      onCompleted: (_) async => completions++,
    );
    final paused = (await controller.load())!;
    await tester.pumpWidget(MaterialApp(
        home: FullscreenClockPage(
      session: paused,
      repository: repository,
      controller: controller,
    )));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(controller.session!.status, FocusStatus.running);
    expect(
        await controller.tick(started.add(const Duration(minutes: 2))), isTrue);
    expect((await repository.get(session.id)).status, FocusStatus.finished);
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in [FocusMode.countdown, FocusMode.stopwatch]) {
    testWidgets('returning from fullscreen retains resumed $mode state',
        (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = FocusRepository(database);
      final session = await repository.start(FocusDraft(
        plannedMinutes: mode == FocusMode.stopwatch ? 0 : 25,
        mode: mode,
      ));
      await repository.pause(session.id);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: FocusPage()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全屏沉浸大时钟'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.fullscreen_exit));
      await tester.pumpAndSettle();

      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('继续'), findsNothing);
      await tester.tap(find.text('暂停'));
      await tester.pumpAndSettle();
      expect((await repository.get(session.id)).status, FocusStatus.paused);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('white noise failure is visible and the same sound can retry',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play' && ++attempts == 1) {
        throw PlatformException(code: 'AUDIO_ERROR', message: 'prepare failed');
      }
      return true;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: FocusPage()),
    ));
    await tester.pumpAndSettle();
    final rainChip = find.widgetWithText(ChoiceChip, '细雨');
    await tester.ensureVisible(rainChip);
    await tester.tap(rainChip);
    await tester.pumpAndSettle();

    expect(find.text('白噪音播放失败，请重试'), findsOneWidget);
    expect(WhiteNoiseService.instance.currentSoundId, isNull);
    expect(WhiteNoiseService.instance.isPlaying, isFalse);
    await tester.tap(rainChip);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(WhiteNoiseService.instance.currentSoundId, 'rain');
    expect(WhiteNoiseService.instance.isPlaying, isTrue);
    expect(find.text('播放中'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
