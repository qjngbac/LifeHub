import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/food_guide_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/environment_guide_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_stage_view.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/safety_pitfalls_view.dart';
import 'package:lifehub/shared/ui/lifehub_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LifecycleCatalog catalog;

  setUpAll(() {
    final file = File('assets/content/lifecycle_guide/catalog.json');
    final raw = file.readAsStringSync();
    catalog = LifecycleCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: LifeHubTheme.light(),
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('FoodGuide Card & View Tests', () {
    testWidgets('renders, expands, and collapses all food topics', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final topic in catalog.foodTopics) {
        await tester.pumpWidget(
          wrapWithTheme(
            FoodGuideView(
              fruits: const [],
              vegetables: const [],
              seasonCalendar: catalog.seasonCalendar,
              topics: [topic],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Card title should be found
        final titleFinder = find.text(topic.title);
        expect(titleFinder, findsWidgets);

        // Tap to expand
        await tester.tap(titleFinder.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Subsections should be visible
        if (topic.subsections.isNotEmpty) {
          expect(find.text(topic.subsections.first.title), findsWidgets);
        }

        // Tap open detail sheet
        final openButtons = find.byIcon(Icons.open_in_new);
        if (openButtons.evaluate().isNotEmpty) {
          await tester.tap(openButtons.last);
          await tester.pumpAndSettle();
          expect(find.textContaining('食物指南'), findsWidgets);
          // Tap barrier to dismiss
          await tester.tapAt(const Offset(50, 50));
          await tester.pumpAndSettle();
        }

        // Tap again to collapse
        await tester.tap(titleFinder.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('LifecycleStage Card & View Tests', () {
    testWidgets('renders, switches and expands all stages without error', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (var i = 0; i < catalog.stages.length; i++) {
        final stage = catalog.stages[i];
        await tester.pumpWidget(
          wrapWithTheme(
            LifecycleStageView(
              stages: catalog.stages,
              checkupSchedule: catalog.checkupSchedule,
              key: ValueKey('stage_view_$i'), initialStageIndex: i,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Failed on stage ');

        if (stage.subsections.isNotEmpty) {
          final firstSub = stage.subsections.first;
          final titleFinder = find.text(firstSub.title);
          expect(titleFinder, findsWidgets);

          // Tap to expand
          await tester.tap(titleFinder.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Tap open detail sheet
          final openButtons = find.byIcon(Icons.open_in_new);
          if (openButtons.evaluate().isNotEmpty) {
            await tester.tap(openButtons.first);
            await tester.pumpAndSettle();
            expect(find.textContaining('人生阶段 · '), findsWidgets);
            await tester.tapAt(const Offset(50, 50));
            await tester.pumpAndSettle();
          }

          // Tap again to collapse
          await tester.tap(titleFinder.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('EnvironmentGuide Card & View Tests', () {
    testWidgets('renders, filters and expands all environment topics without error', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          EnvironmentGuideView(
            topics: catalog.envTopics,
            replacementSchedule: catalog.replacementSchedule,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final categories = ['全部', '居家环境', '日化清洁安全', '衣物鞋袜'];
      for (final cat in categories) {
        final chip = find.widgetWithText(FilterChip, cat);
        if (chip.evaluate().isNotEmpty) {
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Expand first visible topic
        final expandIcons = find.byIcon(Icons.expand_more);
        if (expandIcons.evaluate().isNotEmpty) {
          await tester.tap(expandIcons.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Tap open detail sheet
          final openButtons = find.byIcon(Icons.open_in_new);
          if (openButtons.evaluate().isNotEmpty) {
            await tester.tap(openButtons.first);
            await tester.pumpAndSettle();
            expect(find.textContaining('日用环境'), findsWidgets);
            await tester.tapAt(const Offset(50, 50));
            await tester.pumpAndSettle();
          }

          // Collapse back
          final collapseIcons = find.byIcon(Icons.expand_less);
          if (collapseIcons.evaluate().isNotEmpty) {
            await tester.tap(collapseIcons.first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        }
      }
    });
  });

  group('SafetyPitfalls Exercise Prescriptions Tests', () {
    testWidgets('renders, switches and expands exercise prescriptions cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        wrapWithTheme(
          SafetyPitfallsView(
            drugInteractions: const [],
            rumors: const [],
            checkups: const [],
            exerciseTopics: catalog.exercisePrescriptions,
            commonPitfalls: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify all 8 exercise cards are present
      expect(catalog.exercisePrescriptions.length, 8);

      for (final ex in catalog.exercisePrescriptions) {
        final titleFinder = find.text(ex.title);
        expect(titleFinder, findsOneWidget);

        // Tap to expand
        await tester.tap(titleFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify tables/bullets render
        if (ex.bullets.isNotEmpty) {
          expect(find.text(ex.bullets.first), findsOneWidget);
        }

        // Tap to collapse
        await tester.tap(titleFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // Test scroll up and down in list
      final listView = find.byType(ListView).first;
      await tester.drag(listView, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(listView, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
