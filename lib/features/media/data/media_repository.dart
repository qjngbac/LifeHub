import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/media/domain/media_models.dart';

class MediaSeriesDraft {
  const MediaSeriesDraft({
    required this.title,
    required this.category,
    this.description,
    this.coverPath,
    this.releaseYear,
    this.rating,
    this.note,
  });

  final String title;
  final MediaCategory category;
  final String? description;
  final String? coverPath;
  final int? releaseYear;
  final double? rating;
  final String? note;
}

class MediaEntryDraft {
  const MediaEntryDraft({
    required this.title,
    required this.category,
    required this.entryType,
    this.seriesId,
    this.subtitle,
    this.sortKey,
    this.seasonNumber,
    this.releaseYear,
    this.coverPath,
    this.description,
    this.watchStatus = MediaWatchStatus.plan,
    this.totalEpisodes,
    this.completedEpisodes = 0,
    this.durationSeconds,
    this.playbackPositionSeconds = 0,
    this.lastWatchedAt,
    this.rating,
    this.note,
  });

  final String title;
  final MediaCategory category;
  final MediaEntryType entryType;
  final String? seriesId;
  final String? subtitle;
  final double? sortKey;
  final int? seasonNumber;
  final int? releaseYear;
  final String? coverPath;
  final String? description;
  final MediaWatchStatus watchStatus;
  final int? totalEpisodes;
  final int completedEpisodes;
  final int? durationSeconds;
  final int playbackPositionSeconds;
  final DateTime? lastWatchedAt;
  final double? rating;
  final String? note;
}

class MediaLocalSearchResult {
  const MediaLocalSearchResult({
    required this.id,
    required this.title,
    required this.isSeries,
    required this.category,
    this.subtitle,
  });

  final String id;
  final String title;
  final bool isSeries;
  final MediaCategory category;
  final String? subtitle;
}

class MediaSeriesSummary {
  const MediaSeriesSummary({
    required this.totalEntries,
    required this.completedEntries,
    required this.current,
    required this.next,
  });

  final int totalEntries;
  final int completedEntries;
  final MediaEntry? current;
  final MediaEntry? next;
}

class MediaRepository {
  MediaRepository(this._database);
  final AppDatabase _database;

  Future<MediaSeriesEntry> createSeries(MediaSeriesDraft draft) {
    _validateSeries(draft);
    return _database.into(_database.mediaSeries).insertReturning(
          MediaSeriesCompanion.insert(
            title: draft.title.trim(),
            category: draft.category.dbValue,
            description: Value(_optional(draft.description)),
            coverPath: Value(_optional(draft.coverPath)),
            releaseYear: Value(draft.releaseYear),
            rating: Value(draft.rating),
            note: Value(_optional(draft.note)),
          ),
        );
  }

  Future<MediaSeriesEntry> updateSeries(
      String id, MediaSeriesDraft draft) async {
    _validateSeries(draft);
    final now = _now();
    await (_database.update(_database.mediaSeries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MediaSeriesCompanion(
      title: Value(draft.title.trim()),
      category: Value(draft.category.dbValue),
      description: Value(_optional(draft.description)),
      coverPath: Value(_optional(draft.coverPath)),
      releaseYear: Value(draft.releaseYear),
      rating: Value(draft.rating),
      note: Value(_optional(draft.note)),
      updatedAt: Value(now),
    ));
    final entries = await listEntries(seriesId: id);
    if (entries.any((entry) => entry.category != draft.category.dbValue)) {
      await (_database.update(_database.mediaEntries)
            ..where((row) => row.seriesId.equals(id) & row.deletedAt.isNull()))
          .write(MediaEntriesCompanion(
        category: Value(draft.category.dbValue),
        updatedAt: Value(now),
      ));
    }
    return (await getSeries(id))!;
  }

  Future<MediaSeriesEntry?> getSeries(String id) =>
      (_database.select(_database.mediaSeries)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<MediaSeriesEntry>> listSeries({MediaCategory? category}) {
    final query = _database.select(_database.mediaSeries)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (category != null) {
          expression = expression & row.category.equals(category.dbValue);
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.title)]);
    return query.get();
  }

  Future<MediaEntry> createEntry(MediaEntryDraft draft) async {
    await _validateEntry(draft);
    final sortKey = draft.sortKey ?? await _nextSortKey(draft.seriesId);
    return _database.into(_database.mediaEntries).insertReturning(
          MediaEntriesCompanion.insert(
            seriesId: Value(draft.seriesId),
            category: draft.category.dbValue,
            entryType: draft.entryType.dbValue,
            title: draft.title.trim(),
            subtitle: Value(_optional(draft.subtitle)),
            sortKey: Value(sortKey),
            seasonNumber: Value(draft.seasonNumber),
            releaseYear: Value(draft.releaseYear),
            coverPath: Value(_optional(draft.coverPath)),
            description: Value(_optional(draft.description)),
            watchStatus: Value(draft.watchStatus.dbValue),
            totalEpisodes: Value(draft.totalEpisodes),
            completedEpisodes: Value(draft.completedEpisodes),
            durationSeconds: Value(draft.durationSeconds),
            playbackPositionSeconds: Value(draft.playbackPositionSeconds),
            lastWatchedAt: Value(draft.lastWatchedAt?.millisecondsSinceEpoch),
            completedAt: Value(
              draft.watchStatus == MediaWatchStatus.completed
                  ? (draft.lastWatchedAt ?? DateTime.now())
                      .millisecondsSinceEpoch
                  : null,
            ),
            rating: Value(draft.rating),
            note: Value(_optional(draft.note)),
          ),
        );
  }

  Future<MediaEntry> updateEntry(String id, MediaEntryDraft draft) async {
    await _validateEntry(draft);
    final existing = await _requireEntry(id);
    final completedAt = draft.watchStatus == MediaWatchStatus.completed
        ? existing.completedAt ?? _now()
        : null;
    await (_database.update(_database.mediaEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MediaEntriesCompanion(
      seriesId: Value(draft.seriesId),
      category: Value(draft.category.dbValue),
      entryType: Value(draft.entryType.dbValue),
      title: Value(draft.title.trim()),
      subtitle: Value(_optional(draft.subtitle)),
      sortKey: Value(draft.sortKey ?? existing.sortKey),
      seasonNumber: Value(draft.seasonNumber),
      releaseYear: Value(draft.releaseYear),
      coverPath: Value(_optional(draft.coverPath)),
      description: Value(_optional(draft.description)),
      watchStatus: Value(draft.watchStatus.dbValue),
      totalEpisodes: Value(draft.totalEpisodes),
      completedEpisodes: Value(draft.completedEpisodes),
      durationSeconds: Value(draft.durationSeconds),
      playbackPositionSeconds: Value(draft.playbackPositionSeconds),
      lastWatchedAt: Value(draft.lastWatchedAt?.millisecondsSinceEpoch),
      completedAt: Value(completedAt),
      rating: Value(draft.rating),
      note: Value(_optional(draft.note)),
      updatedAt: Value(_now()),
    ));
    return _requireEntry(id);
  }

  Future<MediaEntry?> getEntry(String id) =>
      (_database.select(_database.mediaEntries)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<MediaEntry>> listEntries({
    MediaCategory? category,
    String? seriesId,
    MediaWatchStatus? status,
    bool independentOnly = false,
  }) {
    final query = _database.select(_database.mediaEntries)
      ..where((row) {
        var expression = row.deletedAt.isNull();
        if (category != null) {
          expression = expression & row.category.equals(category.dbValue);
        }
        if (seriesId != null) {
          expression = expression & row.seriesId.equals(seriesId);
        } else if (independentOnly) {
          expression = expression & row.seriesId.isNull();
        }
        if (status != null) {
          expression = expression & row.watchStatus.equals(status.dbValue);
        }
        return expression;
      })
      ..orderBy([
        (row) => OrderingTerm(expression: row.sortKey),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.get();
  }

  Future<List<MediaEntry>> continueWatching({int limit = 10}) {
    final query = _database.select(_database.mediaEntries)
      ..where((row) =>
          row.deletedAt.isNull() &
          row.watchStatus.equals(MediaWatchStatus.watching.dbValue))
      ..orderBy([
        (row) => OrderingTerm.desc(row.lastWatchedAt),
        (row) => OrderingTerm.desc(row.updatedAt),
      ])
      ..limit(limit);
    return query.get();
  }

  Future<List<MediaLocalSearchResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final pattern = '%${term.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final series = await (_database.select(_database.mediaSeries)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.title.like(pattern) |
                  row.description.like(pattern) |
                  row.note.like(pattern)))
          ..limit(50))
        .get();
    final entries = await (_database.select(_database.mediaEntries)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.title.like(pattern) |
                  row.subtitle.like(pattern) |
                  row.description.like(pattern) |
                  row.note.like(pattern)))
          ..limit(100))
        .get();
    return [
      ...series.map((item) => MediaLocalSearchResult(
            id: item.id,
            title: item.title,
            isSeries: true,
            category: MediaCategory.fromDb(item.category),
            subtitle: '系列',
          )),
      ...entries.map((item) => MediaLocalSearchResult(
            id: item.id,
            title: item.title,
            isSeries: false,
            category: MediaCategory.fromDb(item.category),
            subtitle: item.subtitle,
          )),
    ];
  }

  Future<MediaEntry> updateEpisodeProgress(
    String id,
    int completedEpisodes, {
    DateTime? now,
  }) async {
    final entry = await _requireEntry(id);
    final update = MediaProgressRules.updateEpisodes(
      current: entry.completedEpisodes,
      delta: completedEpisodes - entry.completedEpisodes,
      total: entry.totalEpisodes,
      status: MediaWatchStatus.fromDb(entry.watchStatus),
      now: now ?? DateTime.now(),
    );
    await (_database.update(_database.mediaEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MediaEntriesCompanion(
      completedEpisodes: Value(update.value),
      watchStatus: Value(update.status.dbValue),
      lastWatchedAt: Value(update.lastWatchedAt.millisecondsSinceEpoch),
      completedAt: Value(update.completedAt?.millisecondsSinceEpoch),
      updatedAt: Value(_now()),
    ));
    return _requireEntry(id);
  }

  Future<MediaEntry> updateMoviePosition(
    String id,
    int positionSeconds, {
    DateTime? now,
  }) async {
    final entry = await _requireEntry(id);
    final update = MediaProgressRules.updateMoviePosition(
      positionSeconds: positionSeconds,
      durationSeconds: entry.durationSeconds,
      status: MediaWatchStatus.fromDb(entry.watchStatus),
      now: now ?? DateTime.now(),
    );
    await (_database.update(_database.mediaEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MediaEntriesCompanion(
      playbackPositionSeconds: Value(update.value),
      watchStatus: Value(update.status.dbValue),
      lastWatchedAt: Value(update.lastWatchedAt.millisecondsSinceEpoch),
      completedAt: Value(update.completedAt?.millisecondsSinceEpoch),
      updatedAt: Value(_now()),
    ));
    return _requireEntry(id);
  }

  Future<MediaEntry> setStatus(String id, MediaWatchStatus status) async {
    final now = _now();
    await (_database.update(_database.mediaEntries)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MediaEntriesCompanion(
      watchStatus: Value(status.dbValue),
      lastWatchedAt: status == MediaWatchStatus.watching
          ? Value(now)
          : const Value.absent(),
      completedAt: Value(status == MediaWatchStatus.completed ? now : null),
      updatedAt: Value(now),
    ));
    return _requireEntry(id);
  }

  Future<void> reorderEntries(String seriesId, List<String> orderedIds) async {
    final existing = await listEntries(seriesId: seriesId);
    if (existing.map((entry) => entry.id).toSet().length != orderedIds.length ||
        !existing.every((entry) => orderedIds.contains(entry.id))) {
      throw ArgumentError('排序列表必须包含系列中的全部作品且不得重复。');
    }
    await _database.transaction(() async {
      for (var index = 0; index < orderedIds.length; index++) {
        await (_database.update(_database.mediaEntries)
              ..where((row) => row.id.equals(orderedIds[index])))
            .write(MediaEntriesCompanion(
          sortKey: Value((index + 1) * 10.0),
          updatedAt: Value(_now()),
        ));
      }
    });
  }

  Future<MediaEntry?> nextEntry(String currentId) async {
    final current = await _requireEntry(currentId);
    if (current.seriesId == null) return null;
    final entries = await listEntries(seriesId: current.seriesId);
    final nextId = MediaProgressRules.nextEntryId(
      currentId: current.id,
      entries: entries
          .map((entry) => MediaSequenceItem(
                id: entry.id,
                sortKey: entry.sortKey,
                completed:
                    entry.watchStatus == MediaWatchStatus.completed.dbValue,
              ))
          .toList(),
    );
    return nextId == null ? null : getEntry(nextId);
  }

  Future<MediaSeriesSummary> seriesSummary(String seriesId) async {
    final entries = await listEntries(seriesId: seriesId);
    final completed = entries
        .where(
            (entry) => entry.watchStatus == MediaWatchStatus.completed.dbValue)
        .length;
    MediaEntry? current;
    for (final entry in entries) {
      if (entry.watchStatus == MediaWatchStatus.watching.dbValue) {
        current = entry;
        break;
      }
    }
    if (current == null) {
      for (final entry in entries) {
        if (entry.watchStatus != MediaWatchStatus.completed.dbValue) {
          current = entry;
          break;
        }
      }
    }
    final next = current == null ? null : await nextEntry(current.id);
    return MediaSeriesSummary(
      totalEntries: entries.length,
      completedEntries: completed,
      current: current,
      next: next,
    );
  }

  Future<void> deleteSeries(String id, {bool deleteEntries = false}) async {
    final now = _now();
    await _database.transaction(() async {
      await (_database.update(_database.mediaSeries)
            ..where((row) => row.id.equals(id)))
          .write(MediaSeriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await (_database.update(_database.mediaEntries)
            ..where((row) => row.seriesId.equals(id) & row.deletedAt.isNull()))
          .write(MediaEntriesCompanion(
        seriesId: deleteEntries ? const Value.absent() : const Value(null),
        deletedAt: deleteEntries ? Value(now) : const Value.absent(),
        updatedAt: Value(now),
      ));
    });
  }

  Future<void> deleteEntry(String id) async {
    final now = _now();
    await (_database.update(_database.mediaEntries)
          ..where((row) => row.id.equals(id)))
        .write(MediaEntriesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<MediaEntry> _requireEntry(String id) async {
    final entry = await getEntry(id);
    if (entry == null) throw StateError('影视作品不存在或已删除。');
    return entry;
  }

  Future<double> _nextSortKey(String? seriesId) async {
    final max = _database.mediaEntries.sortKey.max();
    final query = _database.selectOnly(_database.mediaEntries)
      ..addColumns([max]);
    query.where(_database.mediaEntries.deletedAt.isNull() &
        (seriesId == null
            ? _database.mediaEntries.seriesId.isNull()
            : _database.mediaEntries.seriesId.equals(seriesId)));
    final current = (await query.getSingle()).read(max);
    return current == null ? 10 : current + 10;
  }

  Future<void> _validateEntry(MediaEntryDraft draft) async {
    if (draft.title.trim().isEmpty) {
      throw ArgumentError.value(draft.title, 'title');
    }
    _validateRating(draft.rating);
    if (draft.totalEpisodes != null && draft.totalEpisodes! < 0 ||
        draft.completedEpisodes < 0 ||
        draft.totalEpisodes != null &&
            draft.completedEpisodes > draft.totalEpisodes!) {
      throw RangeError('影视集数进度无效');
    }
    if (draft.durationSeconds != null && draft.durationSeconds! < 0 ||
        draft.playbackPositionSeconds < 0 ||
        draft.durationSeconds != null &&
            draft.playbackPositionSeconds > draft.durationSeconds!) {
      throw RangeError('影视播放位置无效');
    }
    if (draft.seriesId != null) {
      final series = await getSeries(draft.seriesId!);
      if (series == null) throw ArgumentError.value(draft.seriesId, 'seriesId');
      if (series.category != draft.category.dbValue) {
        throw ArgumentError('作品分类必须与系列分类一致。');
      }
    }
  }

  static void _validateSeries(MediaSeriesDraft draft) {
    if (draft.title.trim().isEmpty) {
      throw ArgumentError.value(draft.title, 'title');
    }
    _validateRating(draft.rating);
  }
}

int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;
String? _optional(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
void _validateRating(double? value) {
  if (value != null && (value < 0 || value > 10)) {
    throw RangeError.range(value, 0, 10, 'rating');
  }
}
