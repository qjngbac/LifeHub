import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

void main() {
  late AppDatabase database;
  late FinanceRepository repository;
  late AccountRepository accountRepo;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FinanceRepository(database);
    accountRepo = AccountRepository(database);
  });
  tearDown(() => database.close());

  test(
    'parses decimal amounts into integer minor units without float errors',
    () {
      expect(FinanceRepository.parseMinor('0.10'), 10);
      expect(FinanceRepository.parseMinor('12'), 1200);
      expect(FinanceRepository.parseMinor('12.3'), 1230);
      expect(FinanceRepository.parseMinor('12.5+3.5'), 1600);
      expect(FinanceRepository.parseMinor('50 - 15'), 3500);
      expect(() => FinanceRepository.parseMinor('12.345'), throwsArgumentError);
      expect(() => FinanceRepository.parseMinor('-1'), throwsArgumentError);
    },
  );

  test('summarizes income and expense for a calendar month', () async {
    await repository.create(
      FinanceDraft(
        direction: FinanceDirection.income,
        amountMinor: 500000,
        category: 'SALARY',
        occurredAt: DateTime(2026, 8, 1, 9),
      ),
    );
    await repository.create(
      FinanceDraft(
        direction: FinanceDirection.expense,
        amountMinor: 12345,
        category: 'FOOD',
        occurredAt: DateTime(2026, 8, 11, 12),
      ),
    );
    await repository.create(
      FinanceDraft(
        direction: FinanceDirection.expense,
        amountMinor: 100,
        category: 'FOOD',
        occurredAt: DateTime(2026, 9, 1),
      ),
    );

    final summary = await repository.monthlySummary(2026, 8);
    expect(summary.incomeMinor, 500000);
    expect(summary.expenseMinor, 12345);
    expect(summary.netMinor, 487655);
    expect(summary.expenseByCategory, {'FOOD': 12345});
  });

  test('rejects non-positive amounts', () {
    expect(
      () => repository.create(
        FinanceDraft(
          direction: FinanceDirection.expense,
          amountMinor: 0,
          occurredAt: DateTime(2026),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('account management, balance tracking and transfer', () async {
    await accountRepo.ensureDefaultAccounts();
    final accounts = await accountRepo.listAccounts();
    expect(accounts.length, 6);

    final wechat = accounts.firstWhere((a) => a.name == '微信钱包');
    final bank = accounts.firstWhere((a) => a.name == '主要银行卡');
    final platform = accounts.firstWhere((a) => a.name.contains('平台钱包'));

    // Set initial bank balance to 10,000.00
    await accountRepo.adjustBalance(bank.id, 1000000);
    var updatedBank = (await accountRepo.getAccount(bank.id))!;
    expect(updatedBank.balanceMinor, 1000000);

    // Platform withdrawal (e.g. Kuaishou/Douyin提现 500.00 to Bank)
    await repository.create(
      FinanceDraft(
        direction: FinanceDirection.transfer,
        amountMinor: 50000,
        category: 'TRANSFER',
        subCategory: '平台收益提现',
        accountId: platform.id,
        targetAccountId: bank.id,
        occurredAt: DateTime(2026, 8, 2),
        note: '快手收益提现到银行卡',
      ),
    );

    updatedBank = (await accountRepo.getAccount(bank.id))!;
    var updatedPlatform = (await accountRepo.getAccount(platform.id))!;
    expect(updatedBank.balanceMinor, 1050000); // 10,000 + 500
    expect(updatedPlatform.balanceMinor, -50000);

    // Transfer 200.00 from Bank to WeChat wallet
    await repository.create(
      FinanceDraft(
        direction: FinanceDirection.transfer,
        amountMinor: 20000,
        category: 'TRANSFER',
        subCategory: '储蓄充值',
        accountId: bank.id,
        targetAccountId: wechat.id,
        occurredAt: DateTime(2026, 8, 3),
        note: '银行卡充值微信零钱',
      ),
    );

    updatedBank = (await accountRepo.getAccount(bank.id))!;
    var updatedWechat = (await accountRepo.getAccount(wechat.id))!;
    expect(updatedBank.balanceMinor, 1030000); // 10,500 - 200
    expect(updatedWechat.balanceMinor, 20000); // 200

    // Spend 35.00 on Takeout using WeChat wallet
    final expenseEntry = await repository.create(
      FinanceDraft(
        direction: FinanceDirection.expense,
        amountMinor: 3500,
        category: 'FOOD',
        subCategory: '外卖便当',
        accountId: wechat.id,
        expenseNature: ExpenseNature.want,
        tags: ['外卖', '夜宵'],
        occurredAt: DateTime(2026, 8, 3, 21),
        note: '美团外卖夜宵',
      ),
    );

    updatedWechat = (await accountRepo.getAccount(wechat.id))!;
    expect(updatedWechat.balanceMinor, 16500); // 200 - 35 = 165.00

    // Verify rich monthly summary
    final richSummary = await repository.richMonthlySummary(2026, 8);
    expect(richSummary.transferCount, 2);
    expect(richSummary.expenseMinor, 3500);
    expect(richSummary.wantMinor, 3500);
    expect(richSummary.needMinor, 0);
    expect(richSummary.expenseBySubCategory['外卖便当'], 3500);
    expect(richSummary.tagBreakdown['夜宵'], 3500);

    // Revert/delete expense and verify balance restores
    await repository.delete(expenseEntry.id);
    updatedWechat = (await accountRepo.getAccount(wechat.id))!;
    expect(updatedWechat.balanceMinor, 20000);
  });

  test(
    'heals legacy reward transfers and restores the account balance',
    () async {
      final account = await accountRepo.create(
        const AccountDraft(name: '旧钱包', accountType: 'WALLET'),
      );
      await accountRepo.adjustBalance(account.id, -6800);
      await database
          .into(database.financeEntries)
          .insert(
            FinanceEntriesCompanion.insert(
              id: const Value('legacy-reward'),
              direction: FinanceDirection.transfer,
              amountMinor: 6800,
              category: const Value('TRANSFER'),
              subCategory: const Value('活动奖励'),
              occurredAt: DateTime(2026, 10, 7).millisecondsSinceEpoch,
              accountId: Value(account.id),
              note: const Value('68元活动奖励'),
            ),
          );

      expect(await repository.healMisclassifiedTransfers(), 1);
      expect(await repository.healMisclassifiedTransfers(), 0);
      final healed =
          (await database.select(database.financeEntries).get()).single;
      expect(healed.direction, FinanceDirection.income);
      expect(healed.category, 'SIDE_INCOME');
      expect(healed.subCategory, '活动奖励');
      expect((await accountRepo.getAccount(account.id))!.balanceMinor, 6800);
    },
  );

  test(
    'reimbursement flow isolates pending expense and resolves cleanly',
    () async {
      // Pay 150.00 for colleague dinner (Pending Reimbursement)
      final reimbursable = await repository.create(
        FinanceDraft(
          direction: FinanceDirection.expense,
          amountMinor: 15000,
          category: 'FOOD',
          subCategory: '聚餐宴请',
          isReimbursable: true,
          reimburseStatus: 'UNPAID',
          occurredAt: DateTime(2026, 8, 5),
          note: '帮同事垫付工作餐',
        ),
      );

      // Summary does NOT count unpaid reimbursable as living expense!
      var summary = await repository.monthlySummary(2026, 8);
      expect(summary.expenseMinor, 0);

      var richSummary = await repository.richMonthlySummary(2026, 8);
      expect(richSummary.pendingReimburseMinor, 15000);
      expect(richSummary.expenseMinor, 0);

      // Later, colleague pays back
      await repository.markReimbursed(reimbursable.id);
      richSummary = await repository.richMonthlySummary(2026, 8);
      expect(richSummary.pendingReimburseMinor, 0);
    },
  );
}
