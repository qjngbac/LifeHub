import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

class BillImportResult {
  BillImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.totalExpenseMinor,
    required this.totalIncomeMinor,
  });

  final int importedCount;
  final int skippedCount;
  final int totalExpenseMinor;
  final int totalIncomeMinor;
}

class BillImportService {
  BillImportService(this._database);
  final AppDatabase _database;

  /// Check which items already exist in the database to prevent duplicate writes.
  Future<void> checkDuplicates(List<ParsedBillItem> items) async {
    if (items.isEmpty) return;

    // Load recent finance entries (e.g. past 1-2 years or all)
    final existingEntries = await (_database.select(_database.financeEntries)
          ..where((row) => row.deletedAt.isNull()))
        .get();

    final existingOrderIds = <String>{};
    final existingSignatures = <String>{};

    for (final entry in existingEntries) {
      if (entry.note != null && entry.note!.isNotEmpty) {
        // Check orderId embedded in note
        final match = RegExp(r'\[单号:\s*([a-zA-Z0-9_\-]+)\]').firstMatch(entry.note!);
        if (match != null) {
          existingOrderIds.add(match.group(1)!);
        }
      }
      // Signature: occurredAt_amountMinor
      existingSignatures.add('${entry.occurredAt}_${entry.amountMinor}');
    }

    for (final item in items) {
      if (item.orderId.isNotEmpty && existingOrderIds.contains(item.orderId)) {
        item.isDuplicate = true;
        item.selected = false;
        continue;
      }

      final sig = '${item.transactionTime.millisecondsSinceEpoch}_${item.amountMinor}';
      if (existingSignatures.contains(sig)) {
        item.isDuplicate = true;
        item.selected = false;
      }
    }
  }

  /// Match suggested account for parsed items based on existing accounts.
  Future<void> autoAssignAccounts(List<ParsedBillItem> items) async {
    final accountRepo = AccountRepository(_database);
    final accounts = await accountRepo.listAccounts();
    if (accounts.isEmpty) {
      await accountRepo.ensureDefaultAccounts();
    }
    final refreshed = await accountRepo.listAccounts();

    FinanceAccountEntry? wechatWallet;
    FinanceAccountEntry? alipayWallet;
    FinanceAccountEntry? defaultDebit;

    for (final a in refreshed) {
      if (a.name.contains('微信')) wechatWallet = a;
      if (a.name.contains('支付宝')) alipayWallet = a;
      if (a.accountType == FinanceAccountType.debit && defaultDebit == null) {
        defaultDebit = a;
      }
    }

    for (final item in items) {
      if (item.assignedAccountId != null) continue;

      if (item.direction == FinanceDirection.transfer) {
        if (item.subCategory == '零钱提现' || item.description.contains('提现')) {
          item.assignedAccountId = (item.sourceType == BillSourceType.alipay ? alipayWallet : wechatWallet)?.id;
          item.assignedTargetAccountId = defaultDebit?.id;
        } else if (item.subCategory == '储蓄充值' ||
            item.subCategory == '零钱充值' ||
            item.description.contains('充值')) {
          item.assignedAccountId = defaultDebit?.id;
          item.assignedTargetAccountId = (item.sourceType == BillSourceType.alipay ? alipayWallet : wechatWallet)?.id;
        } else {
          item.assignedAccountId = (item.sourceType == BillSourceType.alipay ? alipayWallet : wechatWallet)?.id;
          item.assignedTargetAccountId = defaultDebit?.id;
        }
        continue;
      }

      if (item.sourceType == BillSourceType.bank) {
        final cardAccount = refreshed.firstWhere(
          (a) =>
              (a.cardLastFour != null &&
                  a.cardLastFour!.isNotEmpty &&
                  item.sourcePaymentMethod.contains(a.cardLastFour!)) ||
              (item.sourcePaymentMethod.contains('招商') && a.name.contains('招商')),
          orElse: () => defaultDebit ?? (refreshed.isNotEmpty ? refreshed.first : defaultDebit!),
        );

        if (item.direction == FinanceDirection.transfer) {
          if (item.subCategory == '账户转入' ||
              item.subCategory == '定存支取' ||
              item.description.contains('网联收款')) {
            item.assignedTargetAccountId = cardAccount.id;
            item.assignedAccountId = wechatWallet?.id ?? alipayWallet?.id;
          } else if (item.subCategory == '定存理财' ||
              item.description.contains('享定存开户起息')) {
            item.assignedAccountId = cardAccount.id;
            item.assignedTargetAccountId = null;
          } else {
            item.assignedAccountId = cardAccount.id;
            item.assignedTargetAccountId = wechatWallet?.id ?? alipayWallet?.id;
          }
        } else {
          item.assignedAccountId = cardAccount.id;
        }
      } else if (item.sourceType == BillSourceType.wechat) {
        if (item.sourcePaymentMethod.contains('银行') ||
            item.sourcePaymentMethod.contains('卡')) {
          item.assignedAccountId = defaultDebit?.id ?? wechatWallet?.id;
        } else {
          item.assignedAccountId = wechatWallet?.id;
        }
      } else if (item.sourceType == BillSourceType.alipay) {
        if (item.sourcePaymentMethod.contains('银行') ||
            item.sourcePaymentMethod.contains('卡')) {
          item.assignedAccountId = defaultDebit?.id ?? alipayWallet?.id;
        } else {
          item.assignedAccountId = alipayWallet?.id;
        }
      } else {
        item.assignedAccountId = wechatWallet?.id ?? alipayWallet?.id;
      }
    }
  }

  /// Batch import selected items inside a transaction.
  Future<BillImportResult> importBatch(List<ParsedBillItem> items) async {
    final toImport = items.where((e) => e.selected && !e.isDuplicate).toList();
    if (toImport.isEmpty) {
      return BillImportResult(
        importedCount: 0,
        skippedCount: items.length,
        totalExpenseMinor: 0,
        totalIncomeMinor: 0,
      );
    }

    final accountRepo = AccountRepository(_database);
    int totalExpense = 0;
    int totalIncome = 0;

    await _database.transaction(() async {
      for (final item in toImport) {
        final accountId = item.assignedAccountId;
        final targetAccountId = item.assignedTargetAccountId;

        final descClean = item.description.trim();
        final partyClean = item.counterparty.trim();
        final hasDesc = descClean.isNotEmpty && descClean != '/';
        final hasParty = partyClean.isNotEmpty && partyClean != '/';

        String note;
        if (hasParty && hasDesc) {
          if (descClean == partyClean || descClean.startsWith(partyClean)) {
            note = descClean;
          } else {
            note = '$partyClean - $descClean';
          }
        } else if (hasParty) {
          note = partyClean;
        } else if (hasDesc) {
          note = descClean;
        } else {
          note = item.subCategory ?? item.category;
        }

        if (item.orderId.isNotEmpty) {
          note = '$note [单号: ${item.orderId}]';
        }

        final tagsJson = item.tags.isNotEmpty ? jsonEncode(item.tags) : null;

        await _database.into(_database.financeEntries).insert(
              FinanceEntriesCompanion.insert(
                direction: item.direction,
                amountMinor: item.amountMinor,
                currency: const Value('CNY'),
                category: Value(item.category),
                subCategory: Value(item.subCategory),
                accountId: Value(accountId),
                targetAccountId: Value(targetAccountId),
                expenseNature: Value(item.expenseNature),
                isReimbursable: const Value(false),
                reimburseStatus: const Value(null),
                tagsJson: Value(tagsJson),
                occurredAt: item.transactionTime.millisecondsSinceEpoch,
                note: Value(note),
              ),
            );

        // Atomically update account balances
        if (item.direction == FinanceDirection.transfer) {
          if (accountId != null) {
            await accountRepo.adjustBalance(accountId, -item.amountMinor);
          }
          if (targetAccountId != null) {
            await accountRepo.adjustBalance(targetAccountId, item.amountMinor);
          }
        } else if (item.direction == FinanceDirection.income) {
          totalIncome += item.amountMinor;
          if (accountId != null) {
            await accountRepo.adjustBalance(accountId, item.amountMinor);
          }
        } else {
          totalExpense += item.amountMinor;
          if (accountId != null) {
            await accountRepo.adjustBalance(accountId, -item.amountMinor);
          }
        }
      }
    });

    return BillImportResult(
      importedCount: toImport.length,
      skippedCount: items.length - toImport.length,
      totalExpenseMinor: totalExpense,
      totalIncomeMinor: totalIncome,
    );
  }
}
