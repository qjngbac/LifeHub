import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class CycleDraft {
  const CycleDraft({
    required this.relationshipId,
    required this.start,
    this.end,
    this.note,
  });

  final String relationshipId;
  final DateTime start;
  final DateTime? end;
  final String? note;
}

class CycleRepository {
  CycleRepository(this._database);

  final AppDatabase _database;

  Future<CycleRecordEntry> create(CycleDraft draft) async {
    final values = await _validate(draft);
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.cycleRecords).insert(
            CycleRecordsCompanion.insert(
              id: Value(id),
              relationshipId: draft.relationshipId,
              startDate: values.$1,
              endDate: Value(values.$2),
              note: Value(_optional(draft.note)),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<CycleRecordEntry> get(String id) async {
    final value = await (_database.select(_database.cycleRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (value == null) throw StateError('Cycle record not found: $id');
    return value;
  }

  Future<CycleRecordEntry> update(String id, CycleDraft draft) async {
    final current = await get(id);
    final values = await _validate(draft);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.cycleRecords)
            ..where((row) => row.id.equals(id)))
          .write(CycleRecordsCompanion(
        relationshipId: Value(draft.relationshipId),
        startDate: Value(values.$1),
        endDate: Value(values.$2),
        note: Value(_optional(draft.note)),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<CycleRecordEntry>> forMonth(
    String relationshipId,
    DateTime month,
  ) {
    final first = DateKeys.toLocalDateKey(DateTime(month.year, month.month));
    final last =
        DateKeys.toLocalDateKey(DateTime(month.year, month.month + 1, 0));
    final query = _database.select(_database.cycleRecords)
      ..where((row) =>
          row.relationshipId.equals(relationshipId) &
          row.startDate.isSmallerOrEqualValue(last) &
          (row.endDate.isNull() | row.endDate.isBiggerOrEqualValue(first)) &
          row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.startDate)]);
    return query.get();
  }

  bool containsDate(CycleRecordEntry record, DateTime date) {
    final key = DateKeys.toLocalDateKey(date);
    return key >= record.startDate &&
        (record.endDate == null || key <= record.endDate!);
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.cycleRecords)
            ..where((row) => row.id.equals(id)))
          .write(CycleRecordsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  Future<(int, int?)> _validate(CycleDraft draft) async {
    final relationship = await (_database.select(_database.relationshipProfiles)
          ..where((row) =>
              row.id.equals(draft.relationshipId) &
              row.deletedAt.isNull() &
              row.active.equals(true)))
        .getSingleOrNull();
    if (relationship == null) {
      throw StateError('Relationship not found: ${draft.relationshipId}');
    }
    final start = DateKeys.toLocalDateKey(draft.start);
    final end = draft.end == null ? null : DateKeys.toLocalDateKey(draft.end!);
    if (end != null && end < start) {
      throw ArgumentError('Cycle end cannot be before its start.');
    }
    return (start, end);
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'CYCLE',
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
