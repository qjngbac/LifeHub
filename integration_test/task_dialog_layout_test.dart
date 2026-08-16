import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifehub/app/app.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 200,
}) async {
  for (var frame = 0; frame < maxFrames; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for the expected widget.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('quick task editor keeps its fixed chrome above the keyboard',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('lifehub.onboarding.completed', true);
    final database = AppDatabase();
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const LifeHubApp(),
    ));
    await _pumpUntilVisible(tester, find.text('＋'));

    await tester.tap(find.text('＋').last);
    await _pumpUntilVisible(tester, find.text('任务'));
    await tester.tap(find.text('任务').last);
    await _pumpUntilVisible(tester, find.byType(KeyboardSafeFormDialog));

    expect(find.byType(KeyboardSafeFormDialog), findsOneWidget);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('任务标题'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
