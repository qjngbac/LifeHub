import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class AnniversaryDraft {
  const AnniversaryDraft({
    required this.title,
    required this.date,
    this.repeatYearly = true,
    this.category = 'LIFE',
    this.relationshipId,
    this.showInToday = true,
  });

  final String title;
  final DateTime date;
  final bool repeatYearly;
  final String category;
  final String? relationshipId;
  final bool showInToday;
}

class AnniversaryRepository {
  AnniversaryRepository(this._database);

  final AppDatabase _database;

  Future<AnniversaryEntry> create(AnniversaryDraft draft) async {
    final title = _validate(draft);
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.anniversaries).insert(
            AnniversariesCompanion.insert(
              id: Value(id),
              title: title,
              date: DateKeys.toLocalDateKey(draft.date),
              repeatYearly: Value(draft.repeatYearly),
              category: Value(draft.category.trim().isEmpty
                  ? 'LIFE'
                  : draft.category.trim()),
              relationshipId: Value(_optional(draft.relationshipId)),
              showInToday: Value(draft.showInToday),
            ),
          );
      await _log(id, 'CREATE');
    });
    return get(id);
  }

  Future<AnniversaryEntry> get(String id) async {
    final value = await (_database.select(_database.anniversaries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (value == null) throw StateError('Anniversary not found: $id');
    return value;
  }

  Future<AnniversaryEntry> update(String id, AnniversaryDraft draft) async {
    final current = await get(id);
    final title = _validate(draft);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.anniversaries)
            ..where((row) => row.id.equals(id)))
          .write(AnniversariesCompanion(
        title: Value(title),
        date: Value(DateKeys.toLocalDateKey(draft.date)),
        repeatYearly: Value(draft.repeatYearly),
        category: Value(
            draft.category.trim().isEmpty ? 'LIFE' : draft.category.trim()),
        relationshipId: Value(_optional(draft.relationshipId)),
        showInToday: Value(draft.showInToday),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<AnniversaryEntry>> list({String? relationshipId}) {
    final relation = _optional(relationshipId);
    final query = _database.select(_database.anniversaries)
      ..where((row) {
        final context = relation == null
            ? row.relationshipId.isNull()
            : row.relationshipId.equals(relation);
        return context & row.deletedAt.isNull();
      })
      ..orderBy([(row) => OrderingTerm(expression: row.date)]);
    return query.get();
  }

  Future<List<AnniversaryEntry>> listAll() {
    final query = _database.select(_database.anniversaries)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.date)]);
    return query.get();
  }

  DateTime nextOccurrence(AnniversaryEntry entry, DateTime from) {
    final source = DateKeys.fromLocalDateKey(entry.date);
    final today = DateTime(from.year, from.month, from.day);
    if (!entry.repeatYearly) return source;
    var candidate = _anniversaryInYear(source, today.year);
    if (candidate.isBefore(today)) {
      candidate = _anniversaryInYear(source, today.year + 1);
    }
    return candidate;
  }

  int daysUntil(AnniversaryEntry entry, DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    return nextOccurrence(entry, today).difference(today).inDays;
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.anniversaries)
            ..where((row) => row.id.equals(id)))
          .write(AnniversariesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  static String _validate(AnniversaryDraft draft) {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    return title;
  }

  static DateTime _anniversaryInYear(DateTime source, int year) {
    final maxDay = DateTime(year, source.month + 1, 0).day;
    return DateTime(year, source.month, source.day.clamp(1, maxDay));
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'ANNIVERSARY',
              entityId: id,
              operation: operation,
            ),
          );

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
