import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

export 'package:lifehub/features/finance/domain/finance_models.dart';

class FinanceSummary {
  const FinanceSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.expenseByCategory,
  });

  final int incomeMinor;
  final int expenseMinor;
  final Map<String, int> expenseByCategory;
  int get netMinor => incomeMinor - expenseMinor;
}

class FinanceRepository {
  FinanceRepository(this._database);
  final AppDatabase _database;

  static int parseMinor(String input) {
    final value = input.trim();
    if (value.contains('+') || (value.contains('-') && !value.startsWith('-'))) {
      final calculated = _evalSimpleMath(value);
      if (calculated != null && calculated > 0) {
        return (calculated * 100).round();
      }
    }
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
    if (match == null) throw ArgumentError.value(input, 'amount');
    final major = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final result = major * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
    if (result <= 0) throw ArgumentError.value(input, 'amount');
    return result;
  }

  static double? _evalSimpleMath(String expr) {
    try {
      final sanitized = expr.replaceAll(' ', '');
      final parts = sanitized.split(RegExp(r'(?<=[+-])|(?=[+-])'));
      if (parts.isEmpty) return null;
      double total = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i += 2) {
        if (i + 1 >= parts.length) break;
        final op = parts[i];
        final val = double.parse(parts[i + 1]);
        if (op == '+') total += val;
        if (op == '-') total -= val;
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  Future<FinanceEntry> create(FinanceDraft draft) async {
    _validate(draft);
    return _database.transaction(() async {
      final entry = await _database.into(_database.financeEntries).insertReturning(
            FinanceEntriesCompanion.insert(
              direction: draft.direction,
              amountMinor: draft.amountMinor,
              currency: Value(draft.currency),
              category: Value(draft.category),
              occurredAt: draft.occurredAt.millisecondsSinceEpoch,
              note: Value(_optional(draft.note)),
              sensitive: Value(draft.sensitive),
              accountId: Value(draft.accountId),
              targetAccountId: Value(draft.targetAccountId),
              subCategory: Value(draft.subCategory),
              expenseNature: Value(draft.expenseNature),
              isReimbursable: Value(draft.isReimbursable),
              reimburseStatus: Value(draft.isReimbursable
                  ? (draft.reimburseStatus ?? 'UNPAID')
                  : null),
              tagsJson: Value(draft.tags.isNotEmpty ? jsonEncode(draft.tags) : null),
              relatedEntryId: Value(draft.relatedEntryId),
            ),
          );

      if (draft.accountId != null) {
        if (draft.direction == FinanceDirection.expense) {
          await _adjustAccountBalance(draft.accountId!, -draft.amountMinor);
        } else if (draft.direction == FinanceDirection.income) {
          await _adjustAccountBalance(draft.accountId!, draft.amountMinor);
        } else if (draft.direction == FinanceDirection.transfer) {
          await _adjustAccountBalance(draft.accountId!, -draft.amountMinor);
          if (draft.targetAccountId != null) {
            await _adjustAccountBalance(draft.targetAccountId!, draft.amountMinor);
          }
        }
      }

      return entry;
    });
  }

  Future<void> _adjustAccountBalance(String accountId, int deltaMinor) async {
    final account = await (_database.select(_database.financeAccounts)
          ..where((row) => row.id.equals(accountId) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (account != null) {
      final newBalance = account.balanceMinor + deltaMinor;
      await (_database.update(_database.financeAccounts)
            ..where((row) => row.id.equals(accountId)))
          .write(FinanceAccountsCompanion(
        balanceMinor: Value(newBalance),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        version: Value(account.version + 1),
      ));
    }
  }

  Future<List<FinanceEntry>> list({
    DateTime? start,
    DateTime? end,
    String? direction,
    String? category,
    String? accountId,
    bool? isReimbursable,
    String? reimburseStatus,
  }) {
    final query = _database.select(_database.financeEntries)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (start != null) {
          expression = expression &
              row.occurredAt.isBiggerOrEqualValue(start.millisecondsSinceEpoch);
        }
        if (end != null) {
          expression = expression &
              row.occurredAt.isSmallerThanValue(end.millisecondsSinceEpoch);
        }
        if (direction != null) {
          expression = expression & row.direction.equals(direction);
        }
        if (category != null) {
          expression = expression & row.category.equals(category);
        }
        if (accountId != null) {
          expression = expression &
              (row.accountId.equals(accountId) |
                  row.targetAccountId.equals(accountId));
        }
        if (isReimbursable != null) {
          expression = expression & row.isReimbursable.equals(isReimbursable);
        }
        if (reimburseStatus != null) {
          expression = expression & row.reimburseStatus.equals(reimburseStatus);
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.desc(row.occurredAt)]);
    return query.get();
  }

  Future<FinanceSummary> monthlySummary(int year, int month) async {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final rows = await list(start: start, end: end);
    var income = 0;
    var expense = 0;
    final categories = <String, int>{};
    for (final row in rows) {
      if (row.direction == FinanceDirection.income) {
        income += row.amountMinor;
      } else if (row.direction == FinanceDirection.expense) {
        if (row.isReimbursable && row.reimburseStatus == 'UNPAID') {
          continue;
        }
        expense += row.amountMinor;
        categories.update(
          row.category,
          (value) => value + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );
      }
    }
    return FinanceSummary(
      incomeMinor: income,
      expenseMinor: expense,
      expenseByCategory: categories,
    );
  }

  Future<RichFinanceSummary> richMonthlySummary(int year, int month) async {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final rows = await list(start: start, end: end);

    int income = 0;
    int expense = 0;
    int transfers = 0;
    int need = 0;
    int want = 0;
    int pendingReimburse = 0;

    final expCat = <String, int>{};
    final incCat = <String, int>{};
    final expSubCat = <String, int>{};
    final daily = <int, int>{};
    final tags = <String, int>{};

    for (final row in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(row.occurredAt);
      final day = dt.day;

      if (row.isReimbursable && row.reimburseStatus == 'UNPAID') {
        pendingReimburse += row.amountMinor;
      }

      if (row.direction == FinanceDirection.income) {
        income += row.amountMinor;
        incCat.update(
          row.category,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );
      } else if (row.direction == FinanceDirection.expense) {
        if (row.isReimbursable && row.reimburseStatus == 'UNPAID') {
          continue;
        }
        expense += row.amountMinor;

        if (row.expenseNature == ExpenseNature.want) {
          want += row.amountMinor;
        } else {
          need += row.amountMinor;
        }

        expCat.update(
          row.category,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );

        final subKey = row.subCategory?.isNotEmpty == true
            ? row.subCategory!
            : row.category;
        expSubCat.update(
          subKey,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );

        daily.update(
          day,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );

        if (row.tagsJson != null && row.tagsJson!.isNotEmpty) {
          try {
            final parsedTags = jsonDecode(row.tagsJson!) as List;
            for (final t in parsedTags) {
              final tagStr = t.toString();
              tags.update(
                tagStr,
                (v) => v + row.amountMinor,
                ifAbsent: () => row.amountMinor,
              );
            }
          } catch (_) {}
        }
      } else if (row.direction == FinanceDirection.transfer) {
        transfers++;
      }
    }

    return RichFinanceSummary(
      incomeMinor: income,
      expenseMinor: expense,
      transferCount: transfers,
      needMinor: need,
      wantMinor: want,
      pendingReimburseMinor: pendingReimburse,
      expenseByCategory: expCat,
      incomeByCategory: incCat,
      expenseBySubCategory: expSubCat,
      dailyExpense: daily,
      tagBreakdown: tags,
    );
  }

  Future<void> markReimbursed(String id, {String? targetAccountId}) async {
    final entry = await (_database.select(_database.financeEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (entry == null) return;

    await _database.transaction(() async {
      await (_database.update(_database.financeEntries)
            ..where((row) => row.id.equals(id)))
          .write(FinanceEntriesCompanion(
        reimburseStatus: const Value('REIMBURSED'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        version: Value(entry.version + 1),
      ));

      if (targetAccountId != null) {
        await _adjustAccountBalance(targetAccountId, entry.amountMinor);
      }
    });
  }

  Future<void> update(String id, FinanceDraft draft) async {
    _validate(draft);
    final old = await (_database.select(_database.financeEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (old == null) return;

    await _database.transaction(() async {
      if (old.accountId != null) {
        if (old.direction == FinanceDirection.expense) {
          await _adjustAccountBalance(old.accountId!, old.amountMinor);
        } else if (old.direction == FinanceDirection.income) {
          await _adjustAccountBalance(old.accountId!, -old.amountMinor);
        } else if (old.direction == FinanceDirection.transfer) {
          await _adjustAccountBalance(old.accountId!, old.amountMinor);
          if (old.targetAccountId != null) {
            await _adjustAccountBalance(old.targetAccountId!, -old.amountMinor);
          }
        }
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await (_database.update(_database.financeEntries)
            ..where((row) => row.id.equals(id)))
          .write(FinanceEntriesCompanion(
        direction: Value(draft.direction),
        amountMinor: Value(draft.amountMinor),
        currency: Value(draft.currency),
        category: Value(draft.category),
        subCategory: Value(draft.subCategory),
        accountId: Value(draft.accountId),
        targetAccountId: Value(draft.targetAccountId),
        expenseNature: Value(draft.expenseNature),
        isReimbursable: Value(draft.isReimbursable),
        reimburseStatus: Value(draft.isReimbursable
            ? (draft.reimburseStatus ?? old.reimburseStatus ?? 'UNPAID')
            : null),
        tagsJson: Value(draft.tags.isNotEmpty ? jsonEncode(draft.tags) : null),
        relatedEntryId: Value(draft.relatedEntryId),
        occurredAt: Value(draft.occurredAt.millisecondsSinceEpoch),
        note: Value(_optional(draft.note)),
        sensitive: Value(draft.sensitive),
        updatedAt: Value(now),
        version: Value(old.version + 1),
      ));

      if (draft.accountId != null) {
        if (draft.direction == FinanceDirection.expense) {
          await _adjustAccountBalance(draft.accountId!, -draft.amountMinor);
        } else if (draft.direction == FinanceDirection.income) {
          await _adjustAccountBalance(draft.accountId!, draft.amountMinor);
        } else if (draft.direction == FinanceDirection.transfer) {
          await _adjustAccountBalance(draft.accountId!, -draft.amountMinor);
          if (draft.targetAccountId != null) {
            await _adjustAccountBalance(draft.targetAccountId!, draft.amountMinor);
          }
        }
      }
    });
  }

  Future<void> delete(String id) async {
    final entry = await (_database.select(_database.financeEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (entry == null) return;

    await _database.transaction(() async {
      if (entry.accountId != null) {
        if (entry.direction == FinanceDirection.expense) {
          await _adjustAccountBalance(entry.accountId!, entry.amountMinor);
        } else if (entry.direction == FinanceDirection.income) {
          await _adjustAccountBalance(entry.accountId!, -entry.amountMinor);
        } else if (entry.direction == FinanceDirection.transfer) {
          await _adjustAccountBalance(entry.accountId!, entry.amountMinor);
          if (entry.targetAccountId != null) {
            await _adjustAccountBalance(entry.targetAccountId!, -entry.amountMinor);
          }
        }
      }

      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await (_database.update(_database.financeEntries)
            ..where((row) => row.id.equals(id)))
          .write(FinanceEntriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(entry.version + 1),
      ));
    });
  }

  /// Automatically heals historical bill entries that were misclassified as transfers
  /// and restores the associated account balance.
  Future<int> healMisclassifiedTransfers() =>
      _database.healMisclassifiedTransfers();

  /// Automatically heals historical campus card recharges and financial repayments.
  Future<int> healCampusAndRepaymentEntries() =>
      _database.healCampusAndRepaymentEntries();

  /// Automatically heals historical food and takeout entries in database.
  Future<int> healFoodSubcategories() =>
      _database.healFoodSubcategories();

  static void _validate(FinanceDraft draft) {
    if (draft.amountMinor <= 0) {
      throw ArgumentError.value(draft.amountMinor, 'amountMinor');
    }
    if (draft.direction != FinanceDirection.income &&
        draft.direction != FinanceDirection.expense &&
        draft.direction != FinanceDirection.transfer) {
      throw ArgumentError.value(draft.direction, 'direction');
    }
    if (draft.currency.trim().isEmpty || draft.category.trim().isEmpty) {
      throw ArgumentError('Currency and category are required.');
    }
  }
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
