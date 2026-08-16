import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:uuid/uuid.dart';

class MoodDraft {
  const MoodDraft({
    required this.date,
    required this.moodCode,
    this.intensity = 3,
    this.note,
    this.relationshipId,
  });

  final DateTime date;
  final String moodCode;
  final int intensity;
  final String? note;
  final String? relationshipId;
}

class MoodRepository {
  MoodRepository(this._database);

  final AppDatabase _database;

  Future<MoodLogEntry> save(MoodDraft draft) async {
    _validate(draft);
    final localDate = DateKeys.toLocalDateKey(draft.date);
    final relationshipId = _optional(draft.relationshipId);
    final contextKey = relationshipId == null ? 'SELF' : 'REL:$relationshipId';
    final existing = await (_database.select(_database.moodLogs)
          ..where((row) =>
              row.localDate.equals(localDate) &
              row.contextKey.equals(contextKey) &
              row.deletedAt.isNull()))
        .getSingleOrNull();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (existing == null) {
      final id = const Uuid().v4();
      await _database.transaction(() async {
        await _database.into(_database.moodLogs).insert(
              MoodLogsCompanion.insert(
                id: Value(id),
                localDate: localDate,
                moodCode: draft.moodCode,
                intensity: Value(draft.intensity),
                note: Value(_optional(draft.note)),
                contextKey: Value(contextKey),
                relationshipId: Value(relationshipId),
              ),
            );
        await _log(id, 'CREATE');
      });
      return get(id);
    }
    await _database.transaction(() async {
      await (_database.update(_database.moodLogs)
            ..where((row) => row.id.equals(existing.id)))
          .write(MoodLogsCompanion(
        moodCode: Value(draft.moodCode),
        intensity: Value(draft.intensity),
        note: Value(_optional(draft.note)),
        relationshipId: Value(relationshipId),
        updatedAt: Value(now),
        version: Value(existing.version + 1),
      ));
      await _log(existing.id, 'UPDATE');
    });
    return get(existing.id);
  }

  Future<MoodLogEntry> get(String id) async {
    final value = await (_database.select(_database.moodLogs)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (value == null) throw StateError('Mood not found: $id');
    return value;
  }

  Future<MoodLogEntry?> forDate(
    DateTime date, {
    String? relationshipId,
  }) {
    final key = DateKeys.toLocalDateKey(date);
    final relation = _optional(relationshipId);
    final context = relation == null ? 'SELF' : 'REL:$relation';
    return (_database.select(_database.moodLogs)
          ..where((row) =>
              row.localDate.equals(key) &
              row.contextKey.equals(context) &
              row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<MoodLogEntry>> forMonth(
    DateTime month, {
    String? relationshipId,
  }) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final relation = _optional(relationshipId);
    final context = relation == null ? 'SELF' : 'REL:$relation';
    final query = _database.select(_database.moodLogs)
      ..where((row) =>
          row.localDate.isBiggerOrEqualValue(DateKeys.toLocalDateKey(first)) &
          row.localDate.isSmallerOrEqualValue(DateKeys.toLocalDateKey(last)) &
          row.contextKey.equals(context) &
          row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.localDate)]);
    return query.get();
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.moodLogs)
            ..where((row) => row.id.equals(id)))
          .write(MoodLogsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  static void _validate(MoodDraft draft) {
    if (!MoodCatalog.contains(draft.moodCode)) {
      throw ArgumentError.value(draft.moodCode, 'moodCode');
    }
    if (draft.intensity < 1 || draft.intensity > 5) {
      throw ArgumentError.value(draft.intensity, 'intensity');
    }
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'MOOD',
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
