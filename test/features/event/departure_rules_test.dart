import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/event/domain/departure_rules.dart';

void main() {
  test('departure subtracts travel and preparation from event start', () {
    final start = DateTime(2026, 8, 12, 9);
    expect(
      DepartureRules.suggestedDepartureAt(
        start: start,
        travelMinutes: 30,
        preparationMinutes: 15,
      ),
      DateTime(2026, 8, 12, 8, 15),
    );
  });

  test('negative departure durations are rejected', () {
    expect(
      () => DepartureRules.suggestedDepartureAt(
        start: DateTime(2026, 8, 12),
        travelMinutes: -1,
        preparationMinutes: 0,
      ),
      throwsRangeError,
    );
  });
}
