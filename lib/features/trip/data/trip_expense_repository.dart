import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

abstract final class TripExpenseCategory {
  static const transport = 'TRANSPORT';
  static const lodging = 'LODGING';
  static const food = 'FOOD';
  static const ticket = 'TICKET';
  static const shopping = 'SHOPPING';
  static const other = 'OTHER';
  static const values = {transport, lodging, food, ticket, shopping, other};
}

class TripExpenseDraft {
  const TripExpenseDraft({
    required this.tripId,
    required this.title,
    required this.amountCents,
    required this.expenseDate,
    this.currency = 'CNY',
    this.category = TripExpenseCategory.other,
    this.payer,
    this.notes,
  });
  final String tripId;
  final String title;
  final int amountCents;
  final DateTime expenseDate;
  final String currency;
  final String category;
  final String? payer;
  final String? notes;
}

class TripExpenseRepository {
  TripExpenseRepository(this._database);
  final AppDatabase _database;

  Future<TripExpenseEntry> create(TripExpenseDraft draft) async {
    final trip = await (_database.select(_database.tripProfiles)
          ..where(
              (row) => row.id.equals(draft.tripId) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (trip == null) throw StateError('Trip not found: ${draft.tripId}');
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    if (draft.amountCents <= 0) {
      throw ArgumentError.value(draft.amountCents, 'amountCents');
    }
    final currency = draft.currency.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError.value(draft.currency, 'currency');
    }
    if (!TripExpenseCategory.values.contains(draft.category)) {
      throw ArgumentError.value(draft.category, 'category');
    }
    final date = DateKeys.toLocalDateKey(draft.expenseDate);
    if (date < trip.startDate || date > trip.endDate) {
      throw ArgumentError('Expense date is outside the trip date range.');
    }
    final id = const Uuid().v4();
    await _database.into(_database.tripExpenses).insert(
          TripExpensesCompanion.insert(
            id: Value(id),
            tripId: draft.tripId,
            title: title,
            amountCents: draft.amountCents,
            currency: Value(currency),
            expenseDate: date,
            category: Value(draft.category),
            payer: Value(_optional(draft.payer)),
            notes: Value(_optional(draft.notes)),
          ),
        );
    return (_database.select(_database.tripExpenses)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<TripExpenseEntry>> list(String tripId) =>
      (_database.select(_database.tripExpenses)
            ..where((row) => row.deletedAt.isNull() & row.tripId.equals(tripId))
            ..orderBy([(row) => OrderingTerm(expression: row.expenseDate)]))
          .get();

  Future<Map<String, int>> totalsByCurrency(String tripId) async {
    final result = <String, int>{};
    for (final expense in await list(tripId)) {
      result.update(
        expense.currency,
        (value) => value + expense.amountCents,
        ifAbsent: () => expense.amountCents,
      );
    }
    return result;
  }

  Future<Map<String, Map<String, int>>> categoryTotals(String tripId) async {
    final result = <String, Map<String, int>>{};
    for (final expense in await list(tripId)) {
      final byCategory = result.putIfAbsent(expense.currency, () => {});
      byCategory.update(
        expense.category,
        (value) => value + expense.amountCents,
        ifAbsent: () => expense.amountCents,
      );
    }
    return result;
  }

  Future<Map<String, Map<String, int>>> payerTotals(String tripId) async {
    final result = <String, Map<String, int>>{};
    for (final expense in await list(tripId)) {
      final payer = expense.payer?.trim().isNotEmpty == true
          ? expense.payer!.trim()
          : '未填写';
      final byPayer = result.putIfAbsent(expense.currency, () => {});
      byPayer.update(
        payer,
        (value) => value + expense.amountCents,
        ifAbsent: () => expense.amountCents,
      );
    }
    return result;
  }

  Future<void> delete(String id) async {
    final current = await (_database.select(_database.tripExpenses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (current == null) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.tripExpenses)
          ..where((row) => row.id.equals(id)))
        .write(TripExpensesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
