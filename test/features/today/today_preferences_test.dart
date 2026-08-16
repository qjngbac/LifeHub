import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/today/application/today_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('uses normalized defaults and persists order and collapsed modules',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final subject = TodayPreferences(preferences);

    expect(subject.loadOrder(), TodayPreferences.defaultOrder);

    await subject.saveOrder(['habits', 'unknown', 'tasks']);
    expect(subject.loadOrder().take(2), ['habits', 'tasks']);
    expect(
      subject.loadOrder().toSet(),
      TodayPreferences.defaultOrder.toSet(),
    );

    await subject.setCollapsed('events', true);
    expect(subject.loadCollapsed(), {'events'});
    await subject.setCollapsed('events', false);
    expect(subject.loadCollapsed(), isEmpty);
  });
}
