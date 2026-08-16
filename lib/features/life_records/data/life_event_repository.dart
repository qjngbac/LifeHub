import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class LifeEventDraft {
  const LifeEventDraft({
    required this.title,
    required this.date,
    this.timeMinutes,
    this.eventType = 'LIFE',
    this.note,
    this.relationshipId,
  });

  final String title;
  final DateTime date;
  final int? timeMinutes;
  final String eventType;
  final String? note;
  final String? relationshipId;
}

class LifeEventRepository {
  LifeEventRepository(this._database);

  final AppDatabase _database;

  Future<LifeEventEntry> create(LifeEventDraft draft) async {
    final title = _validate(draft);
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.lifeEvents).insert(
            LifeEventsCompanion.insert(
              id: Value(id),
              title: title,
              localDate: DateKeys.toLocalDateKey(draft.date),
              timeMinutes: Value(draft.timeMinutes),
              eventType: Value(draft.eventType.trim().isEmpty
                  ? 'LIFE'
                  : draft.eventType.trim()),
              note: Value(_optional(draft.note)),
              relationshipId: Value(_optional(draft.relationshipId)),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<LifeEventEntry> get(String id) async {
    final value = await (_database.select(_database.lifeEvents)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (value == null) throw StateError('Life event not found: $id');
    return value;
  }

  Future<LifeEventEntry> update(String id, LifeEventDraft draft) async {
    final current = await get(id);
    final title = _validate(draft);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lifeEvents)
            ..where((row) => row.id.equals(id)))
          .write(LifeEventsCompanion(
        title: Value(title),
        localDate: Value(DateKeys.toLocalDateKey(draft.date)),
        timeMinutes: Value(draft.timeMinutes),
        eventType: Value(
            draft.eventType.trim().isEmpty ? 'LIFE' : draft.eventType.trim()),
        note: Value(_optional(draft.note)),
        relationshipId: Value(_optional(draft.relationshipId)),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<LifeEventEntry>> forDate(
    DateTime date, {
    String? relationshipId,
  }) {
    final key = DateKeys.toLocalDateKey(date);
    final relation = _optional(relationshipId);
    final query = _database.select(_database.lifeEvents)
      ..where((row) {
        final context = relation == null
            ? row.relationshipId.isNull()
            : row.relationshipId.equals(relation);
        return row.localDate.equals(key) & context & row.deletedAt.isNull();
      })
      ..orderBy([
        (row) => OrderingTerm(
              expression: row.timeMinutes,
              nulls: NullsOrder.last,
            ),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.get();
  }

  Future<List<LifeEventEntry>> listRange(
    DateTime start,
    DateTime end, {
    String? relationshipId,
  }) {
    final startKey = DateKeys.toLocalDateKey(start);
    final endKey = DateKeys.toLocalDateKey(end);
    if (endKey < startKey) throw ArgumentError('Invalid date range.');
    final relation = _optional(relationshipId);
    final query = _database.select(_database.lifeEvents)
      ..where((row) {
        final context = relation == null
            ? row.relationshipId.isNull()
            : row.relationshipId.equals(relation);
        return row.localDate.isBiggerOrEqualValue(startKey) &
            row.localDate.isSmallerOrEqualValue(endKey) &
            context &
            row.deletedAt.isNull();
      })
      ..orderBy([
        (row) => OrderingTerm(expression: row.localDate),
        (row) => OrderingTerm(
              expression: row.timeMinutes,
              nulls: NullsOrder.last,
            ),
      ]);
    return query.get();
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lifeEvents)
            ..where((row) => row.id.equals(id)))
          .write(LifeEventsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  static String _validate(LifeEventDraft draft) {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    final minute = draft.timeMinutes;
    if (minute != null && (minute < 0 || minute >= 24 * 60)) {
      throw ArgumentError.value(minute, 'timeMinutes');
    }
    return title;
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'LIFE_EVENT',
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
