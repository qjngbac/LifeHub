import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';

void main() {
  test('monthly renewal clamps to the last day of a shorter month', () {
    expect(
      SubscriptionRules.nextRenewal(
        from: DateTime(2026, 1, 31),
        unit: SubscriptionCycleUnit.month,
      ),
      DateTime(2026, 2, 28),
    );
  });

  test('weekly yearly and fixed-day cycles advance deterministically', () {
    final from = DateTime(2024, 2, 29);
    expect(
      SubscriptionRules.nextRenewal(
        from: from,
        unit: SubscriptionCycleUnit.week,
        interval: 2,
      ),
      DateTime(2024, 3, 14),
    );
    expect(
      SubscriptionRules.nextRenewal(
        from: from,
        unit: SubscriptionCycleUnit.year,
      ),
      DateTime(2025, 2, 28),
    );
    expect(
      SubscriptionRules.nextRenewal(
        from: from,
        unit: SubscriptionCycleUnit.fixedDays,
        fixedDays: 10,
      ),
      DateTime(2024, 3, 10),
    );
  });
}
