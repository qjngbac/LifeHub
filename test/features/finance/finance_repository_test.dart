import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

void main() {
  late AppDatabase database;
  late FinanceRepository repository;
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FinanceRepository(database);
  });
  tearDown(() => database.close());

  test('parses decimal amounts into integer minor units without float errors',
      () {
    expect(FinanceRepository.parseMinor('0.10'), 10);
    expect(FinanceRepository.parseMinor('12'), 1200);
    expect(FinanceRepository.parseMinor('12.3'), 1230);
    expect(() => FinanceRepository.parseMinor('12.345'), throwsArgumentError);
    expect(() => FinanceRepository.parseMinor('-1'), throwsArgumentError);
  });

  test('summarizes income and expense for a calendar month', () async {
    await repository.create(FinanceDraft(
      direction: FinanceDirection.income,
      amountMinor: 500000,
      category: 'SALARY',
      occurredAt: DateTime(2026, 8, 1, 9),
    ));
    await repository.create(FinanceDraft(
      direction: FinanceDirection.expense,
      amountMinor: 12345,
      category: 'FOOD',
      occurredAt: DateTime(2026, 8, 11, 12),
    ));
    await repository.create(FinanceDraft(
      direction: FinanceDirection.expense,
      amountMinor: 100,
      category: 'FOOD',
      occurredAt: DateTime(2026, 9, 1),
    ));

    final summary = await repository.monthlySummary(2026, 8);
    expect(summary.incomeMinor, 500000);
    expect(summary.expenseMinor, 12345);
    expect(summary.netMinor, 487655);
    expect(summary.expenseByCategory, {'FOOD': 12345});
  });

  test('rejects non-positive amounts', () {
    expect(
      () => repository.create(FinanceDraft(
        direction: FinanceDirection.expense,
        amountMinor: 0,
        occurredAt: DateTime(2026),
      )),
      throwsArgumentError,
    );
  });
}
