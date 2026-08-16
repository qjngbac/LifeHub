import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';

abstract final class FinanceDirection {
  static const income = 'INCOME';
  static const expense = 'EXPENSE';
}

class FinanceDraft {
  const FinanceDraft({
    required this.direction,
    required this.amountMinor,
    required this.occurredAt,
    this.currency = 'CNY',
    this.category = 'OTHER',
    this.note,
    this.sensitive = false,
  });

  final String direction;
  final int amountMinor;
  final String currency;
  final String category;
  final DateTime occurredAt;
  final String? note;
  final bool sensitive;
}

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
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value);
    if (match == null) throw ArgumentError.value(input, 'amount');
    final major = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final result = major * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
    if (result <= 0) throw ArgumentError.value(input, 'amount');
    return result;
  }

  Future<FinanceEntry> create(FinanceDraft draft) {
    _validate(draft);
    return _database.into(_database.financeEntries).insertReturning(
          FinanceEntriesCompanion.insert(
            direction: draft.direction,
            amountMinor: draft.amountMinor,
            currency: Value(draft.currency),
            category: Value(draft.category),
            occurredAt: draft.occurredAt.millisecondsSinceEpoch,
            note: Value(_optional(draft.note)),
            sensitive: Value(draft.sensitive),
          ),
        );
  }

  Future<List<FinanceEntry>> list({
    DateTime? start,
    DateTime? end,
    String? direction,
    String? category,
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
      } else {
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

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.financeEntries)
          ..where((row) => row.id.equals(id)))
        .write(FinanceEntriesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  static void _validate(FinanceDraft draft) {
    if (draft.amountMinor <= 0) {
      throw ArgumentError.value(draft.amountMinor, 'amountMinor');
    }
    if (draft.direction != FinanceDirection.income &&
        draft.direction != FinanceDirection.expense) {
      throw ArgumentError.value(draft.direction, 'direction');
    }
    if (draft.currency.trim().isEmpty || draft.category.trim().isEmpty) {
      throw ArgumentError('Currency and category are required.');
    }
  }
}

String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
