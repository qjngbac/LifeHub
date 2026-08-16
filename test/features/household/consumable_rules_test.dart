import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/household/domain/consumable_rules.dart';

void main() {
  test('consumable state reports low stock and expiry', () {
    final state = ConsumableRules.state(
      quantity: 1,
      minimumQuantity: 2,
      expiryDate: DateTime(2026, 8, 15),
      now: DateTime(2026, 8, 11),
      expiringDays: 7,
    );
    expect(state.lowStock, isTrue);
    expect(state.expiringSoon, isTrue);
    expect(state.expired, isFalse);
  });

  test('negative stock is rejected', () {
    expect(
      () => ConsumableRules.state(quantity: -1, now: DateTime(2026, 8, 11)),
      throwsRangeError,
    );
  });
}
