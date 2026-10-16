import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_rules.dart';

class MatchRepository {
  MatchRepository(this._database);

  final AppDatabase _database;

  Future<MatchRecordEntry> create(MatchDraft draft) async {
    _validateForWrite(draft);
    return _insert(draft);
  }

  Future<MatchRecordEntry> update(String id, MatchDraft draft) async {
    _validateForWrite(draft);
    final existing = await _require(id);
    await (_database.update(_database.matchRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(_companion(draft, existing: existing));
    return _require(id);
  }

  Future<List<MatchRecordEntry>> createBatch(List<MatchDraft> drafts) async {
    if (drafts.isEmpty) return const [];
    for (final draft in drafts) {
      _validateForWrite(draft);
    }
    return _database.transaction(() async {
      final result = <MatchRecordEntry>[];
      for (final draft in drafts) {
        result.add(await _insert(draft));
      }
      return result;
    });
  }

  Future<List<MatchRecordEntry>> importBatch(
    List<({MatchDraft draft, String? existingId})> records,
  ) async {
    if (records.isEmpty) return const [];
    return _database.transaction(() async {
      _rejectAmbiguousImport(records);
      final result = <MatchRecordEntry>[];
      for (final record in records) {
        final existingId = record.existingId;
        if (existingId == null) {
          _validateForWrite(record.draft);
          if ((await findPossibleDuplicates(record.draft)).isNotEmpty) {
            throw const FormatException('比赛已存在，请重新确认导入预览。');
          }
          result.add(await _insert(record.draft));
          continue;
        }
        final existing = await _require(existingId);
        final draft = mergeImportDraft(record.draft, existing);
        _validateForWrite(draft);
        await (_database.update(_database.matchRecords)
              ..where(
                  (row) => row.id.equals(existingId) & row.deletedAt.isNull()))
            .write(_companion(draft, existing: existing));
        result.add(await _require(existingId));
      }
      return result;
    });
  }

  Future<MatchRecordEntry?> get(String id) =>
      (_database.select(_database.matchRecords)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<void> delete(String id) async {
    final existing = await _require(id);
    final now = _now();
    await (_database.update(_database.matchRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MatchRecordsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(existing.version + 1),
    ));
  }

  Future<List<MatchRecordEntry>> listUpcoming({
    DateTime? now,
    String? query,
    String? sportType,
    String? competition,
    DateTime? from,
    DateTime? to,
  }) async {
    final current = now ?? DateTime.now();
    final rows = await (_database.select(_database.matchRecords)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm(expression: row.matchDate),
            (row) => OrderingTerm(expression: row.startAt),
          ]))
        .get();
    return rows.where((row) {
      if (row.status != MatchStatuses.scheduled &&
          row.status != MatchStatuses.postponed) {
        return false;
      }
      final date = DateKeys.fromLocalDateKey(row.matchDate);
      if (from != null && date.isBefore(_dateOnly(from))) {
        return false;
      }
      if (to != null && date.isAfter(_dateOnly(to))) {
        return false;
      }
      if (sportType != null &&
          sportType.trim().isNotEmpty &&
          row.sportType != sportType.trim()) {
        return false;
      }
      if (competition != null &&
          competition.trim().isNotEmpty &&
          row.competition != competition.trim()) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final value = query.trim().toLowerCase();
        final haystack = [
          row.sportType,
          row.competition,
          row.participantA,
          row.participantB,
          row.season ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(value)) return false;
      }
      return row.startAt == null ||
          !DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true)
              .isBefore(current.toUtc());
    }).toList(growable: false);
  }

  Future<List<MatchRecordEntry>> listPendingResults({
    required DateTime now,
    String? query,
    String? sportType,
    String? competition,
    DateTime? from,
    DateTime? to,
  }) async {
    await markDuePending(now);
    final rows = await (_database.select(_database.matchRecords)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals(MatchStatuses.pendingResult))
          ..orderBy([(row) => OrderingTerm(expression: row.matchDate)]))
        .get();
    return rows.where((row) {
      final date = DateKeys.fromLocalDateKey(row.matchDate);
      if (from != null && date.isBefore(_dateOnly(from))) return false;
      if (to != null && date.isAfter(_dateOnly(to))) return false;
      if (sportType != null &&
          sportType.trim().isNotEmpty &&
          row.sportType != sportType.trim()) {
        return false;
      }
      if (competition != null &&
          competition.trim().isNotEmpty &&
          row.competition != competition.trim()) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final value = query.trim().toLowerCase();
        final haystack = [
          row.sportType,
          row.competition,
          row.participantA,
          row.participantB,
          row.season ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(value)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<List<MatchRecordEntry>> listArchive({
    String? query,
    int? year,
    String? sportType,
    String? competition,
    String? status,
  }) async {
    final rows = await (_database.select(_database.matchRecords)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.status.equals(MatchStatuses.finished) |
                  row.status.equals(MatchStatuses.cancelled)))
          ..orderBy([(row) => OrderingTerm.desc(row.matchDate)]))
        .get();
    return rows.where((row) {
      final date = DateKeys.fromLocalDateKey(row.matchDate);
      if (year != null && date.year != year) {
        return false;
      }
      if (sportType != null &&
          sportType.trim().isNotEmpty &&
          row.sportType != sportType.trim()) {
        return false;
      }
      if (competition != null &&
          competition.trim().isNotEmpty &&
          row.competition != competition.trim()) {
        return false;
      }
      if (status != null && status.trim().isNotEmpty && row.status != status) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final value = query.trim().toLowerCase();
        final haystack = [
          row.sportType,
          row.competition,
          row.participantA,
          row.participantB,
          row.season ?? '',
          row.scoreDetail ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(value)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<List<MatchRecordEntry>> findPossibleDuplicates(
      MatchDraft draft) async {
    final rows = await (_database.select(_database.matchRecords)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final duplicates = rows
        .where((row) => MatchRules.areDuplicates(_toDraft(row), draft))
        .toList();
    final source = MatchRules.normalizeSourceKey(draft);
    if (source != null) {
      duplicates.sort((first, second) {
        final firstMatches =
            MatchRules.normalizeSourceKey(_toDraft(first)) == source;
        final secondMatches =
            MatchRules.normalizeSourceKey(_toDraft(second)) == source;
        return (firstMatches ? 0 : 1).compareTo(secondMatches ? 0 : 1);
      });
    }
    return duplicates;
  }

  MatchDraft mergeImportDraft(MatchDraft draft, MatchRecordEntry existing) {
    final fields = draft.importFields;
    if (fields == null) return draft;
    T pick<T>(MatchImportField field, T incoming, T stored) =>
        fields.contains(field) ? incoming : stored;
    return MatchDraft(
      sportType: draft.sportType,
      competition: draft.competition,
      participantA: draft.participantA,
      participantB: draft.participantB,
      matchDate: draft.matchDate,
      startAt: draft.startAt,
      timezoneId: draft.timezoneId,
      season: pick(MatchImportField.season, draft.season, existing.season),
      stageOrRound: pick(MatchImportField.stageOrRound, draft.stageOrRound,
          existing.stageOrRound),
      scoreA: pick(MatchImportField.scoreA, draft.scoreA, existing.scoreA),
      scoreB: pick(MatchImportField.scoreB, draft.scoreB, existing.scoreB),
      scoreDetail: pick(MatchImportField.scoreDetail, draft.scoreDetail,
          existing.scoreDetail),
      status: pick(MatchImportField.status, draft.status, existing.status),
      venue: pick(MatchImportField.venue, draft.venue, existing.venue),
      broadcast:
          pick(MatchImportField.broadcast, draft.broadcast, existing.broadcast),
      notes: pick(MatchImportField.notes, draft.notes, existing.notes),
      favorite:
          pick(MatchImportField.favorite, draft.favorite, existing.favorite),
      sourceType: draft.sourceType,
      sourceKey:
          pick(MatchImportField.sourceKey, draft.sourceKey, existing.sourceKey),
      sourceLabel: pick(MatchImportField.sourceLabel, draft.sourceLabel,
          existing.sourceLabel),
      importFields: fields,
    );
  }

  Future<MatchRecordEntry> recordResult(
    String id, {
    int? scoreA,
    int? scoreB,
    String? scoreDetail,
  }) async {
    if ((scoreA == null) != (scoreB == null)) {
      throw const FormatException('比分必须同时填写双方。');
    }
    if (scoreA != null && (scoreA < 0 || scoreB! < 0)) {
      throw const FormatException('比分不能为负数。');
    }
    if (scoreA == null && (scoreDetail == null || scoreDetail.trim().isEmpty)) {
      throw const FormatException('请填写比分或结果说明。');
    }
    final existing = await _require(id);
    await (_database.update(_database.matchRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MatchRecordsCompanion(
      scoreA: Value(scoreA),
      scoreB: Value(scoreB),
      scoreDetail: Value(_optional(scoreDetail)),
      status: const Value(MatchStatuses.finished),
      updatedAt: Value(_now()),
      version: Value(existing.version + 1),
    ));
    return _require(id);
  }

  Future<int> markDuePending(DateTime now) {
    return (_database.update(_database.matchRecords)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals(MatchStatuses.scheduled) &
              row.startAt.isNotNull() &
              row.startAt
                  .isSmallerOrEqualValue(now.toUtc().millisecondsSinceEpoch)))
        .write(MatchRecordsCompanion(
      status: const Value(MatchStatuses.pendingResult),
      updatedAt: Value(_now()),
    ));
  }

  Future<MatchRecordEntry> setStatus(String id, String status) async {
    if (!MatchStatuses.values.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final existing = await _require(id);
    await (_database.update(_database.matchRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MatchRecordsCompanion(
      status: Value(status),
      updatedAt: Value(_now()),
      version: Value(existing.version + 1),
    ));
    return _require(id);
  }

  Future<MatchRecordEntry> postpone(String id) async {
    final existing = await _require(id);
    await (_database.update(_database.matchRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .write(MatchRecordsCompanion(
      status: const Value(MatchStatuses.postponed),
      startAt: const Value(null),
      timezoneId: const Value(null),
      updatedAt: Value(_now()),
      version: Value(existing.version + 1),
    ));
    return _require(id);
  }

  Future<MatchSuggestions> getSuggestions() async {
    final rows = await (_database.select(_database.matchRecords)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final sports = <String>{'足球', '篮球', '网球', '电竞', '羽毛球', '乒乓球', '排球', '棒球'};
    final competitions = <String>{};
    final participants = <String>{};
    final compsBySport = <String, Set<String>>{};
    final partsBySport = <String, Set<String>>{};

    for (final row in rows) {
      final s = row.sportType.trim();
      final c = row.competition.trim();
      final pA = row.participantA.trim();
      final pB = row.participantB.trim();

      if (s.isNotEmpty) sports.add(s);
      if (c.isNotEmpty) {
        competitions.add(c);
        if (s.isNotEmpty) compsBySport.putIfAbsent(s, () => <String>{}).add(c);
      }
      if (pA.isNotEmpty) {
        participants.add(pA);
        if (s.isNotEmpty) partsBySport.putIfAbsent(s, () => <String>{}).add(pA);
      }
      if (pB.isNotEmpty) {
        participants.add(pB);
        if (s.isNotEmpty) partsBySport.putIfAbsent(s, () => <String>{}).add(pB);
      }
    }
    return MatchSuggestions(
      sportTypes: sports.toList(growable: false),
      competitions: competitions.toList(growable: false),
      participants: participants.toList(growable: false),
      competitionsBySport: compsBySport.map(
        (key, val) => MapEntry(key, val.toList(growable: false)),
      ),
      participantsBySport: partsBySport.map(
        (key, val) => MapEntry(key, val.toList(growable: false)),
      ),
    );
  }

  Future<MatchRecordEntry> _insert(MatchDraft draft) {
    return _database
        .into(_database.matchRecords)
        .insertReturning(_companion(draft));
  }

  void _rejectAmbiguousImport(
    List<({MatchDraft draft, String? existingId})> records,
  ) {
    final existingIds = <String>{};
    final drafts = <MatchDraft>[];
    for (final record in records) {
      final existingId = record.existingId;
      if ((existingId != null && !existingIds.add(existingId)) ||
          drafts
              .any((draft) => MatchRules.areDuplicates(draft, record.draft))) {
        throw const FormatException('同一批次包含重复比赛，无法保存。');
      }
      drafts.add(record.draft);
    }
  }

  MatchRecordsCompanion _companion(
    MatchDraft draft, {
    MatchRecordEntry? existing,
  }) {
    final clearSchedule = draft.status == MatchStatuses.postponed;
    final values = MatchRecordsCompanion(
      sportType: Value(draft.sportType!.trim()),
      competition: Value(draft.competition!.trim()),
      season: Value(_optional(draft.season)),
      stageOrRound: Value(_optional(draft.stageOrRound)),
      participantA: Value(draft.participantA!.trim()),
      participantB: Value(draft.participantB!.trim()),
      matchDate: Value(DateKeys.toLocalDateKey(draft.matchDate!)),
      startAt: Value(
        clearSchedule ? null : draft.startAt?.toUtc().millisecondsSinceEpoch,
      ),
      timezoneId: Value(clearSchedule ? null : _optional(draft.timezoneId)),
      scoreA: Value(draft.scoreA),
      scoreB: Value(draft.scoreB),
      scoreDetail: Value(_optional(draft.scoreDetail)),
      status: Value(draft.status),
      venue: Value(_optional(draft.venue)),
      broadcast: Value(_optional(draft.broadcast)),
      notes: Value(_optional(draft.notes)),
      favorite: Value(draft.favorite),
      sourceType: Value(draft.sourceType),
      sourceKey: Value(existing == null &&
              draft.importFields != null &&
              !draft.importFields!.contains(MatchImportField.sourceKey)
          ? null
          : _optional(draft.sourceKey)),
      sourceLabel: Value(existing == null &&
              draft.importFields != null &&
              !draft.importFields!.contains(MatchImportField.sourceLabel)
          ? null
          : _optional(draft.sourceLabel)),
    );
    if (existing == null) return values;
    return values.copyWith(
      updatedAt: Value(_now()),
      version: Value(existing.version + 1),
    );
  }

  void _validateForWrite(MatchDraft draft) {
    final errors = draft
        .validate(now: DateTime.now())
        .where((issue) => issue.severity == MatchIssueSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      throw FormatException(errors.map((issue) => issue.message).join(' '));
    }
  }

  Future<MatchRecordEntry> _require(String id) async {
    final row = await get(id);
    if (row == null) throw StateError('Match not found: $id');
    return row;
  }

  MatchDraft _toDraft(MatchRecordEntry row) => MatchDraft(
        sportType: row.sportType,
        competition: row.competition,
        season: row.season,
        stageOrRound: row.stageOrRound,
        participantA: row.participantA,
        participantB: row.participantB,
        matchDate: DateKeys.fromLocalDateKey(row.matchDate),
        startAt: row.startAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true),
        timezoneId: row.timezoneId,
        scoreA: row.scoreA,
        scoreB: row.scoreB,
        scoreDetail: row.scoreDetail,
        status: row.status,
        venue: row.venue,
        broadcast: row.broadcast,
        notes: row.notes,
        favorite: row.favorite,
        sourceType: row.sourceType,
        sourceKey: row.sourceKey,
        sourceLabel: row.sourceLabel,
      );

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class MatchSuggestions {
  const MatchSuggestions({
    this.sportTypes = const [],
    this.competitions = const [],
    this.participants = const [],
    this.competitionsBySport = const {},
    this.participantsBySport = const {},
  });

  final List<String> sportTypes;
  final List<String> competitions;
  final List<String> participants;
  final Map<String, List<String>> competitionsBySport;
  final Map<String, List<String>> participantsBySport;

  List<String> competitionsFor(String? sport) {
    if (sport != null && sport.trim().isNotEmpty) {
      final matched = competitionsBySport[sport.trim()];
      if (matched != null && matched.isNotEmpty) return matched;
    }
    return competitions;
  }

  List<String> participantsFor(String? sport) {
    if (sport != null && sport.trim().isNotEmpty) {
      final matched = participantsBySport[sport.trim()];
      if (matched != null && matched.isNotEmpty) return matched;
    }
    return participants;
  }
}
