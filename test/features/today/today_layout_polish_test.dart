import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/today/application/today_preferences.dart';
import 'package:lifehub/features/today/presentation/today_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/ui/responsive_test_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting('zh_CN'));
  testWidgets(
    'motto keeps the established header row and task creation remains clear',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await TodayPreferences(preferences).saveMotto('One moment at a time.');
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await configurePhone(
        tester,
        const ResponsiveTestCase('today', size: Size(390, 844), textScale: 1.3),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
          child: const MaterialApp(home: TodayPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getSize(find.byKey(const Key('today_motto'))).width,
        greaterThan(150),
      );
      expect(find.byIcon(Icons.add_task), findsOneWidget);
      expectNoLayoutFailure(tester);
    },
  );
}
