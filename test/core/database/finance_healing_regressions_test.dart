import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

Future<File> _databaseFile() async {
  final directory = await Directory.systemTemp.createTemp('lifehub_healing_');
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/test.sqlite');
}

void main() {
  test('opening the database preserves loan income and its balance', () async {
    final file = await _databaseFile();
    final source = AppDatabase.forTesting(NativeDatabase(file));
    final account = await AccountRepository(
      source,
    ).create(const AccountDraft(name: '钱包', accountType: 'WALLET'));
    await FinanceRepository(source).create(
      FinanceDraft(
        direction: FinanceDirection.income,
        amountMinor: 100000,
        accountId: account.id,
        occurredAt: DateTime(2026, 10, 1),
        note: '借呗放款到账',
      ),
    );
    await source.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    final entry = (await reopened.select(reopened.financeEntries).get()).single;
    expect(entry.direction, FinanceDirection.income);
    expect(
      (await AccountRepository(reopened).getAccount(account.id))!.balanceMinor,
      100000,
    );
  });

  test(
    'opening the database preserves two-account transfers and their reversal',
    () async {
      final file = await _databaseFile();
      final source = AppDatabase.forTesting(NativeDatabase(file));
      final accounts = AccountRepository(source);
      final bank = await accounts.create(
        const AccountDraft(name: '银行卡', accountType: 'DEBIT'),
      );
      final campus = await accounts.create(
        const AccountDraft(name: '校园卡', accountType: 'WALLET'),
      );
      final entry = await FinanceRepository(source).create(
        FinanceDraft(
          direction: FinanceDirection.transfer,
          amountMinor: 1000,
          accountId: bank.id,
          targetAccountId: campus.id,
          category: 'TRANSFER',
          occurredAt: DateTime(2026, 10, 1),
          note: '校园一卡通充值',
        ),
      );
      await source.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(
        (await reopened.select(reopened.financeEntries).get()).single.direction,
        FinanceDirection.transfer,
      );
      await FinanceRepository(reopened).delete(entry.id);
      expect(
        (await AccountRepository(reopened).getAccount(bank.id))!.balanceMinor,
        0,
      );
      expect(
        (await AccountRepository(reopened).getAccount(campus.id))!.balanceMinor,
        0,
      );
    },
  );

  test(
    'opening the database preserves explicit food categories and nature',
    () async {
      final file = await _databaseFile();
      final source = AppDatabase.forTesting(NativeDatabase(file));
      await FinanceRepository(source).create(
        FinanceDraft(
          direction: FinanceDirection.expense,
          amountMinor: 1000,
          category: 'FOOD',
          subCategory: '早餐饮食',
          expenseNature: 'NEED',
          note: '喜茶早餐',
          occurredAt: DateTime(2026, 10, 1, 8),
        ),
      );
      await source.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      final entry =
          (await reopened.select(reopened.financeEntries).get()).single;
      expect(entry.subCategory, '早餐饮食');
      expect(entry.expenseNature, 'NEED');
    },
  );

  test(
    'food healing fills missing categories without replacing expense nature',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await FinanceRepository(database).create(
        FinanceDraft(
          direction: FinanceDirection.expense,
          amountMinor: 1000,
          category: 'FOOD',
          expenseNature: 'WANT',
          occurredAt: DateTime(2026, 10, 1, 12),
        ),
      );
      expect(await database.healFoodSubcategories(), 1);
      final entry =
          (await database.select(database.financeEntries).get()).single;
      expect(entry.subCategory, '外卖午餐');
      expect(entry.expenseNature, 'WANT');
      expect(await database.healFoodSubcategories(), 0);
    },
  );

  test('concurrent reward healing credits each entry only once', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final account = await AccountRepository(
      database,
    ).create(const AccountDraft(name: '钱包', accountType: 'WALLET'));
    await FinanceRepository(database).create(
      FinanceDraft(
        direction: FinanceDirection.transfer,
        amountMinor: 1000,
        accountId: account.id,
        category: 'TRANSFER',
        note: '活动奖励',
        occurredAt: DateTime(2026, 10, 1),
      ),
    );
    final counts = await Future.wait([
      database.healMisclassifiedTransfers(),
      database.healMisclassifiedTransfers(),
    ]);
    expect(counts.reduce((a, b) => a + b), 1);
    expect(
      (await AccountRepository(database).getAccount(account.id))!.balanceMinor,
      1000,
    );
  });

  test(
    'reward healing preserves outgoing red packets and platform payments',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = await AccountRepository(
        database,
      ).create(const AccountDraft(name: '钱包', accountType: 'WALLET'));
      for (final note in ['微信红包转出', '百度网盘音乐套餐']) {
        await FinanceRepository(database).create(
          FinanceDraft(
            direction: FinanceDirection.transfer,
            amountMinor: 1000,
            accountId: account.id,
            category: 'TRANSFER',
            note: note,
            occurredAt: DateTime(2026, 10, 1),
          ),
        );
      }
      expect(await database.healMisclassifiedTransfers(), 0);
      final entries = await database.select(database.financeEntries).get();
      expect(
        entries.every((entry) => entry.direction == FinanceDirection.transfer),
        isTrue,
      );
      expect(
        (await AccountRepository(
          database,
        ).getAccount(account.id))!.balanceMinor,
        -2000,
      );
    },
  );

  test(
    'opening an existing schema 13 database installs the account index',
    () async {
      final file = await _databaseFile();
      final source = AppDatabase.forTesting(NativeDatabase(file));
      await source.select(source.tasks).get();
      await source.customStatement('DROP INDEX idx_finance_account');
      await source.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      final indexes = await reopened
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_finance_account'",
          )
          .get();
      expect(indexes, hasLength(1));
    },
  );

  test(
    'background database connections heal a reward only once on open',
    () async {
      final file = await _databaseFile();
      final source = AppDatabase.forTesting(NativeDatabase(file));
      final account = await AccountRepository(
        source,
      ).create(const AccountDraft(name: '钱包', accountType: 'WALLET'));
      await FinanceRepository(source).create(
        FinanceDraft(
          direction: FinanceDirection.transfer,
          amountMinor: 1000,
          accountId: account.id,
          category: 'TRANSFER',
          note: '活动奖励',
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      await source.close();
      final first = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file),
      );
      final second = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file),
      );
      addTearDown(first.close);
      addTearDown(second.close);
      final entries = await Future.wait([
        first.select(first.financeEntries).get(),
        second.select(second.financeEntries).get(),
      ]);
      expect(
        entries.every(
          (rows) => rows.single.direction == FinanceDirection.income,
        ),
        isTrue,
      );
      expect(
        (await AccountRepository(first).getAccount(account.id))!.balanceMinor,
        1000,
      );
    },
  );

  test(
    'campus healing repairs unclassified one-ended transfers once',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final account = await AccountRepository(
        database,
      ).create(const AccountDraft(name: '钱包', accountType: 'WALLET'));
      await FinanceRepository(database).create(
        FinanceDraft(
          direction: FinanceDirection.transfer,
          amountMinor: 1000,
          accountId: account.id,
          category: 'TRANSFER',
          note: '校园一卡通充值',
          occurredAt: DateTime(2026, 10, 1),
        ),
      );
      expect(await database.healCampusAndRepaymentEntries(), 1);
      final entry =
          (await database.select(database.financeEntries).get()).single;
      expect(entry.direction, FinanceDirection.expense);
      expect(entry.subCategory, '校园一卡通');
      expect(
        (await AccountRepository(
          database,
        ).getAccount(account.id))!.balanceMinor,
        -1000,
      );
      expect(await database.healCampusAndRepaymentEntries(), 0);
    },
  );
}
