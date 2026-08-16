import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/data_hub/application/module_usage_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('suggests only modules observed for 30 days and opened fewer than twice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final tracker = ModuleUsageTracker(await SharedPreferences.getInstance());
    final firstDay = DateTime(2026, 8, 1);
    await tracker
        .observeModules(['tasks', 'courses', 'reading'], now: firstDay);
    await tracker.recordOpen('tasks', now: firstDay);
    await tracker.recordOpen('tasks',
        now: firstDay.add(const Duration(days: 2)));
    await tracker.recordOpen('courses', now: firstDay);

    expect(
      tracker.lowFrequencySuggestions(
        ['tasks', 'courses', 'reading'],
        now: firstDay.add(const Duration(days: 29)),
      ),
      isEmpty,
    );
    expect(
      tracker.lowFrequencySuggestions(
        ['tasks', 'courses', 'reading'],
        now: firstDay.add(const Duration(days: 31)),
      ),
      {'courses', 'reading'},
    );
  });

  test('pinned modules are excluded and reset clears observations', () async {
    SharedPreferences.setMockInitialValues({});
    final tracker = ModuleUsageTracker(await SharedPreferences.getInstance());
    final firstDay = DateTime(2026, 7, 1);
    await tracker.observeModules(['tasks', 'courses'], now: firstDay);

    expect(
      tracker.lowFrequencySuggestions(
        ['tasks', 'courses'],
        pinned: {'tasks'},
        now: DateTime(2026, 8, 11),
      ),
      {'courses'},
    );

    await tracker.reset();
    expect(
      tracker.lowFrequencySuggestions(
        ['tasks', 'courses'],
        now: DateTime(2026, 9, 20),
      ),
      isEmpty,
    );
  });
}
