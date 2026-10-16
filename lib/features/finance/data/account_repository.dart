import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

class AccountNetWorthSummary {
  const AccountNetWorthSummary({
    required this.totalAssetsMinor,
    required this.totalLiabilitiesMinor,
    required this.netWorthMinor,
    required this.accounts,
  });

  final int totalAssetsMinor;
  final int totalLiabilitiesMinor;
  final int netWorthMinor;
  final List<FinanceAccountEntry> accounts;
}

class AccountRepository {
  AccountRepository(this._database);
  final AppDatabase _database;

  Future<List<FinanceAccountEntry>> listAccounts() async {
    final query = _database.select(_database.financeAccounts)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query.get();
  }

  Future<FinanceAccountEntry?> getAccount(String id) async {
    final query = _database.select(_database.financeAccounts)
      ..where((row) => row.id.equals(id) & row.deletedAt.isNull())
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<FinanceAccountEntry> create(AccountDraft draft) async {
    return _database.into(_database.financeAccounts).insertReturning(
          FinanceAccountsCompanion.insert(
            name: draft.name,
            accountType: Value(draft.accountType),
            balanceMinor: Value(draft.balanceMinor),
            currency: Value(draft.currency),
            cardLastFour: Value(draft.cardLastFour),
            color: Value(draft.color),
            iconName: Value(draft.iconName),
            includeInNetWorth: Value(draft.includeInNetWorth),
            billingDay: Value(draft.billingDay),
            repaymentDay: Value(draft.repaymentDay),
            creditLimitMinor: Value(draft.creditLimitMinor),
            notes: Value(draft.notes),
          ),
        );
  }

  Future<void> update(String id, AccountDraft draft) async {
    final existing = await getAccount(id);
    if (existing == null) return;

    await (_database.update(_database.financeAccounts)
          ..where((row) => row.id.equals(id)))
        .write(
      FinanceAccountsCompanion(
        name: Value(draft.name),
        accountType: Value(draft.accountType),
        balanceMinor: Value(draft.balanceMinor),
        currency: Value(draft.currency),
        cardLastFour: Value(draft.cardLastFour),
        color: Value(draft.color),
        iconName: Value(draft.iconName),
        includeInNetWorth: Value(draft.includeInNetWorth),
        billingDay: Value(draft.billingDay),
        repaymentDay: Value(draft.repaymentDay),
        creditLimitMinor: Value(draft.creditLimitMinor),
        notes: Value(draft.notes),
        version: Value(existing.version + 1),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> adjustBalance(String id, int deltaMinor) async {
    final existing = await getAccount(id);
    if (existing == null) return;
    final newBalance = existing.balanceMinor + deltaMinor;

    await (_database.update(_database.financeAccounts)
          ..where((row) => row.id.equals(id)))
        .write(
      FinanceAccountsCompanion(
        balanceMinor: Value(newBalance),
        version: Value(existing.version + 1),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> delete(String id) async {
    final existing = await getAccount(id);
    if (existing == null) return;

    await (_database.update(_database.financeAccounts)
          ..where((row) => row.id.equals(id)))
        .write(
      FinanceAccountsCompanion(
        deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
        version: Value(existing.version + 1),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<AccountNetWorthSummary> getNetWorthSummary() async {
    final accounts = await listAccounts();
    int totalAssets = 0;
    int totalLiabilities = 0;

    for (final acc in accounts) {
      if (!acc.includeInNetWorth) continue;
      if (acc.accountType == FinanceAccountType.credit) {
        // Credit account balance is typically debt (liabilities)
        if (acc.balanceMinor < 0) {
          totalLiabilities += acc.balanceMinor.abs();
        } else {
          // If user paid extra into credit card
          totalAssets += acc.balanceMinor;
        }
      } else {
        if (acc.balanceMinor >= 0) {
          totalAssets += acc.balanceMinor;
        } else {
          totalLiabilities += acc.balanceMinor.abs();
        }
      }
    }

    return AccountNetWorthSummary(
      totalAssetsMinor: totalAssets,
      totalLiabilitiesMinor: totalLiabilities,
      netWorthMinor: totalAssets - totalLiabilities,
      accounts: accounts,
    );
  }

  Future<void> ensureDefaultAccounts() async {
    final accounts = await listAccounts();
    if (accounts.isNotEmpty) return;

    final defaultAccounts = [
      const AccountDraft(
        name: '微信钱包',
        accountType: FinanceAccountType.wallet,
        balanceMinor: 0,
        color: '#07C160',
        notes: '微信零钱 / 零钱通',
      ),
      const AccountDraft(
        name: '支付宝',
        accountType: FinanceAccountType.wallet,
        balanceMinor: 0,
        color: '#1677FF',
        notes: '支付宝余额 / 余额宝',
      ),
      const AccountDraft(
        name: '主要银行卡',
        accountType: FinanceAccountType.debit,
        balanceMinor: 0,
        color: '#096DD9',
        notes: '日常工资与储蓄卡',
      ),
      const AccountDraft(
        name: '信用卡 / 花呗',
        accountType: FinanceAccountType.credit,
        balanceMinor: 0,
        color: '#FA8C16',
        notes: '信用消费与账单分期',
      ),
      const AccountDraft(
        name: '平台钱包 (快手等)',
        accountType: FinanceAccountType.platform,
        balanceMinor: 0,
        color: '#FF4D4F',
        notes: '快手、抖音、电商收益与提现中转',
      ),
      const AccountDraft(
        name: '现金钱包',
        accountType: FinanceAccountType.cash,
        balanceMinor: 0,
        color: '#FAAD14',
        notes: '钱包与备用现金',
      ),
    ];

    for (final draft in defaultAccounts) {
      await create(draft);
    }
  }
}
