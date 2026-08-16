import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/emergency_card_page.dart';

void main() {
  testWidgets('birth date uses a text field with a calendar action',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MedicationRepository(database).saveEmergencyCard(
      EmergencyCardDraft(birthDate: DateTime(2003, 2, 25)),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: EmergencyCardPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2003-02-25'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    final birthField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '出生年月',
    );
    expect(birthField, findsOneWidget);
    expect(tester.widget<TextField>(birthField).controller?.text, '2003-02-25');
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
  });
}
