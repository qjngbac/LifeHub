import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/goal/presentation/goal_detail_page.dart';
import 'package:lifehub/features/parcel/presentation/parcel_detail_page.dart';
import 'package:lifehub/features/reading/presentation/reading_detail_page.dart';
import 'package:lifehub/features/trip/presentation/trip_detail_page.dart';

void main() {
  for (final (name, page) in <(String, Widget)>[
    ('reading', const ReadingDetailPage(itemId: 'record')),
    ('parcel', const ParcelDetailPage(parcelId: 'record')),
    ('goal', const GoalDetailPage(goalId: 'record')),
    ('trip', const TripDetailPage(tripId: 'record')),
  ]) {
    testWidgets('$name missing detail can retry and return', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => page),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('加载失败，记录可能不存在或已删除'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await _seed(database, name);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('重试成功'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('打开'), findsOneWidget);
    });
  }
}

Future<void> _seed(AppDatabase database, String type) async {
  switch (type) {
    case 'reading':
      await database
          .into(database.readingItems)
          .insert(
            ReadingItemsCompanion.insert(
              id: const Value('record'),
              title: '重试成功',
            ),
          );
    case 'parcel':
      await database
          .into(database.parcels)
          .insert(
            ParcelsCompanion.insert(id: const Value('record'), title: '重试成功'),
          );
    case 'goal':
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: const Value('record'),
              name: '重试成功',
              progressMode: const Value('MANUAL'),
              manualProgress: const Value(0.0),
            ),
          );
    case 'trip':
      await database
          .into(database.projects)
          .insert(
            ProjectsCompanion.insert(id: const Value('project'), name: '重试成功'),
          );
      await database
          .into(database.tripProfiles)
          .insert(
            TripProfilesCompanion.insert(
              id: const Value('record'),
              projectId: 'project',
              startDate: 20261001,
              endDate: 20261003,
            ),
          );
  }
}
