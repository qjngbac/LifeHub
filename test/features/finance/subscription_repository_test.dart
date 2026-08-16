import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/data/subscription_repository.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';

void main() {
  test('confirming one cycle creates exactly one linked expense', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = SubscriptionRepository(db);
    final row = await repository.create(SubscriptionDraft(
      name: '云盘会员',
      amountMinor: 1200,
      cycleUnit: SubscriptionCycleUnit.month,
      nextRenewalDate: DateTime(2026, 8, 31),
    ));

    final expense = await repository.confirmCharge(
      row.id,
      cycleDate: 20260831,
      occurredAt: DateTime(2026, 8, 31),
    );

    expect(expense.amountMinor, 1200);
    expect((await repository.get(row.id)).nextRenewalDate, 20260930);
    await expectLater(
      repository.confirmCharge(row.id, cycleDate: 20260831),
      throwsStateError,
    );
    expect(await db.select(db.financeEntries).get(), hasLength(1));
  });
}
