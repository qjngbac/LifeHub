import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';

class ReadingDraft {
  const ReadingDraft({
    required this.title,
    this.author,
    this.readingType = ReadingType.novel,
    this.progressUnit = ReadingUnit.chapter,
    this.currentProgress = 0,
    this.totalProgress,
    this.status = ReadingStatus.planned,
    this.rating,
    this.notes,
    this.coverPath,
  });

  final String title;
  final String? author;
  final ReadingType readingType;
  final ReadingUnit progressUnit;
  final int currentProgress;
  final int? totalProgress;
  final ReadingStatus status;
  final double? rating;
  final String? notes;
  final String? coverPath;
}

class ReadingRepository {
  ReadingRepository(this._database);
  final AppDatabase _database;

  Future<ReadingItemEntry> create(ReadingDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    ReadingProgressRules.fraction(
        current: draft.currentProgress, total: draft.totalProgress);
    if (draft.rating != null && (draft.rating! < 0 || draft.rating! > 10)) {
      throw RangeError('评分必须在 0 到 10 之间');
    }
    return _database.into(_database.readingItems).insertReturning(
          ReadingItemsCompanion.insert(
            title: title,
            author: Value(_optional(draft.author)),
            readingType: Value(draft.readingType.name.toUpperCase()),
            progressUnit: Value(draft.progressUnit.name.toUpperCase()),
            currentProgress: Value(draft.currentProgress),
            totalProgress: Value(draft.totalProgress),
            status: Value(draft.status.dbValue),
            rating: Value(draft.rating),
            notes: Value(_optional(draft.notes)),
            coverPath: Value(_optional(draft.coverPath)),
          ),
        );
  }

  Future<ReadingItemEntry> get(String id) async {
    final row = await (_database.select(_database.readingItems)
          ..where((item) => item.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Reading item not found: $id');
    return row;
  }

  Future<ReadingItemEntry> update(String id, ReadingDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    ReadingProgressRules.fraction(
      current: draft.currentProgress,
      total: draft.totalProgress,
    );
    if (draft.rating != null && (draft.rating! < 0 || draft.rating! > 10)) {
      throw RangeError('评分必须在 0 到 10 之间');
    }
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final completed = draft.totalProgress != null &&
        draft.totalProgress! > 0 &&
        draft.currentProgress == draft.totalProgress;
    await (_database.update(_database.readingItems)
          ..where((item) => item.id.equals(id)))
        .write(ReadingItemsCompanion(
      title: Value(title),
      author: Value(_optional(draft.author)),
      readingType: Value(draft.readingType.name.toUpperCase()),
      progressUnit: Value(draft.progressUnit.name.toUpperCase()),
      currentProgress: Value(draft.currentProgress),
      totalProgress: Value(draft.totalProgress),
      status: Value(completed
          ? ReadingStatus.completed.dbValue
          : draft.currentProgress > 0
              ? ReadingStatus.reading.dbValue
              : draft.status.dbValue),
      rating: Value(draft.rating),
      notes: Value(_optional(draft.notes)),
      coverPath: Value(_optional(draft.coverPath)),
      startedAt: Value(draft.currentProgress > 0
          ? current.startedAt ?? now
          : current.startedAt),
      lastReadAt: Value(draft.currentProgress > 0 ? now : current.lastReadAt),
      completedAt: Value(completed ? now : null),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  Future<List<ReadingItemEntry>> list({String? status}) =>
      (_database.select(_database.readingItems)
            ..where((row) {
              var result = row.deletedAt.isNull();
              if (status != null) result = result & row.status.equals(status);
              return result;
            })
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<List<ReadingItemEntry>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return list();
    final pattern = '%${value.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    return (_database.select(_database.readingItems)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.title.like(pattern) |
                  row.author.like(pattern) |
                  row.notes.like(pattern)))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<List<ReadingItemEntry>> continueReading() => (_database
          .select(_database.readingItems)
        ..where((row) => row.deletedAt.isNull() & row.status.equals('READING'))
        ..orderBy([
          (row) => OrderingTerm.desc(row.lastReadAt),
          (row) => OrderingTerm.desc(row.updatedAt),
        ]))
      .get();

  Future<ReadingItemEntry> updateProgress(String id, int next,
      {DateTime? now}) async {
    final row = await get(id);
    final time = now ?? DateTime.now();
    final update = ReadingProgressRules.update(
      current: row.currentProgress,
      next: next,
      total: row.totalProgress,
      status: ReadingStatus.fromDb(row.status),
      now: time,
    );
    await (_database.update(_database.readingItems)
          ..where((item) => item.id.equals(id)))
        .write(ReadingItemsCompanion(
      currentProgress: Value(update.current),
      status: Value(update.status.dbValue),
      startedAt: Value(
          row.startedAt ?? (next > 0 ? time.millisecondsSinceEpoch : null)),
      lastReadAt: Value(time.millisecondsSinceEpoch),
      completedAt: Value(update.completedAt?.millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(row.version + 1),
    ));
    return get(id);
  }

  Future<void> delete(String id) async {
    final row = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.readingItems)
          ..where((item) => item.id.equals(id)))
        .write(ReadingItemsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(row.version + 1),
    ));
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
