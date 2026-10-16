import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/medication_page.dart';

void main() {
  testWidgets('only plans active today expose normal check-in buttons',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MedicationRepository(database);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await repository.createPlan(MedicationPlanDraft(
      name: '未来计划', startDate: today.add(const Duration(days: 1)),
      reminderTimes: const ['08:00'],
    ));
    await repository.createPlan(MedicationPlanDraft(
      name: '已结束计划', startDate: today.subtract(const Duration(days: 2)),
      endDate: today.subtract(const Duration(days: 1)),
      reminderTimes: const ['09:00'],
    ));
    await repository.createPlan(MedicationPlanDraft(
      name: '当前计划', startDate: today, endDate: today,
      reminderTimes: const ['10:00'],
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MedicationPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('未来计划'), findsOneWidget);
    expect(find.text('已结束计划'), findsOneWidget);
    expect(find.text('08:00 打卡'), findsNothing);
    expect(find.text('09:00 打卡'), findsNothing);
    expect(find.text('10:00 打卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
