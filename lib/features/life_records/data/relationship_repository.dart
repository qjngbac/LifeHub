import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class RelationshipDraft {
  const RelationshipDraft({
    required this.name,
    this.nickname,
    this.relationType = 'PARTNER',
    this.startDate,
    this.birthday,
  });

  final String name;
  final String? nickname;
  final String relationType;
  final DateTime? startDate;
  final DateTime? birthday;
}

class RelationshipRepository {
  RelationshipRepository(this._database);

  final AppDatabase _database;

  Future<RelationshipProfileEntry> create(RelationshipDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError.value(draft.name, 'name');
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.relationshipProfiles).insert(
            RelationshipProfilesCompanion.insert(
              id: Value(id),
              name: name,
              nickname: Value(_optional(draft.nickname)),
              relationType: Value(draft.relationType.trim().isEmpty
                  ? 'PARTNER'
                  : draft.relationType.trim()),
              startDate: Value(_dateKey(draft.startDate)),
              birthday: Value(_dateKey(draft.birthday)),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<RelationshipProfileEntry> get(String id) async {
    final value = await (_database.select(_database.relationshipProfiles)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (value == null) throw StateError('Relationship not found: $id');
    return value;
  }

  Future<RelationshipProfileEntry> update(
    String id,
    RelationshipDraft draft,
  ) async {
    final current = await get(id);
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError.value(draft.name, 'name');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.relationshipProfiles)
            ..where((row) => row.id.equals(id)))
          .write(RelationshipProfilesCompanion(
        name: Value(name),
        nickname: Value(_optional(draft.nickname)),
        relationType: Value(draft.relationType.trim().isEmpty
            ? 'PARTNER'
            : draft.relationType.trim()),
        startDate: Value(_dateKey(draft.startDate)),
        birthday: Value(_dateKey(draft.birthday)),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<RelationshipProfileEntry>> list({
    bool includeArchived = false,
  }) {
    final query = _database.select(_database.relationshipProfiles)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (!includeArchived) filter = filter & row.active.equals(true);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.get();
  }

  Future<void> archive(String id) async {
    final current = await get(id);
    await _setActive(current, false, 'ARCHIVE');
  }

  Future<void> restore(String id) async {
    final current = await get(id);
    await _setActive(current, true, 'RESTORE');
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.relationshipProfiles)
            ..where((row) => row.id.equals(id)))
          .write(RelationshipProfilesCompanion(
        active: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  Future<void> _setActive(
    RelationshipProfileEntry current,
    bool active,
    String operation,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.relationshipProfiles)
            ..where((row) => row.id.equals(current.id)))
          .write(RelationshipProfilesCompanion(
        active: Value(active),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(current.id, operation);
    });
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'RELATIONSHIP',
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int? _dateKey(DateTime? date) =>
      date == null ? null : DateKeys.toLocalDateKey(date);
}
