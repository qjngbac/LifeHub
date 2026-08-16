import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class ReviewSummary {
  const ReviewSummary({
    required this.completedTasks,
    required this.habitCheckIns,
    required this.focusMinutes,
    required this.activeGoals,
    required this.moodDays,
    required this.lifeEvents,
  });

  final int completedTasks;
  final int habitCheckIns;
  final int focusMinutes;
  final int activeGoals;
  final int moodDays;
  final int lifeEvents;

  Map<String, Object?> toJson() => {
        'completedTasks': completedTasks,
        'habitCheckIns': habitCheckIns,
        'focusMinutes': focusMinutes,
        'activeGoals': activeGoals,
        'moodDays': moodDays,
        'lifeEvents': lifeEvents,
      };
}

class ReviewDraft {
  const ReviewDraft({
    required this.periodType,
    required this.start,
    required this.end,
    required this.summary,
    this.wins,
    this.blockers,
    this.nextPriorities,
  });

  final String periodType;
  final DateTime start;
  final DateTime end;
  final ReviewSummary summary;
  final String? wins;
  final String? blockers;
  final String? nextPriorities;
}

class ReviewRepository {
  ReviewRepository(this._database);
  final AppDatabase _database;

  Future<ReviewSummary> summary(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) throw ArgumentError('Invalid review period.');
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final startKey = DateKeys.toLocalDateKey(start);
    final endKey = DateKeys.toLocalDateKey(end);

    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.completedAt.isBiggerOrEqualValue(startMs) &
              row.completedAt.isSmallerThanValue(endMs)))
        .get();
    final habitLogs = await (_database.select(_database.habitLogs)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.localDate.isBiggerOrEqualValue(startKey) &
              row.localDate.isSmallerThanValue(endKey) &
              row.status.equals('DONE')))
        .get();
    final focus = await (_database.select(_database.focusSessions)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('FINISHED') &
              row.endedAt.isBiggerOrEqualValue(startMs) &
              row.endedAt.isSmallerThanValue(endMs)))
        .get();
    final goals = await (_database.select(_database.goals)
          ..where(
              (row) => row.deletedAt.isNull() & row.status.equals('ACTIVE')))
        .get();
    final moods = await (_database.select(_database.moodLogs)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.contextKey.equals('SELF') &
              row.localDate.isBiggerOrEqualValue(startKey) &
              row.localDate.isSmallerThanValue(endKey)))
        .get();
    final events = await (_database.select(_database.lifeEvents)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.relationshipId.isNull() &
              row.localDate.isBiggerOrEqualValue(startKey) &
              row.localDate.isSmallerThanValue(endKey)))
        .get();
    return ReviewSummary(
      completedTasks: tasks.length,
      habitCheckIns: habitLogs.length,
      focusMinutes: focus.fold(
        0,
        (sum, session) => sum + (session.actualMinutes ?? 0),
      ),
      activeGoals: goals.length,
      moodDays: moods.length,
      lifeEvents: events.length,
    );
  }

  Future<ReviewEntry> save(ReviewDraft draft) async {
    if (!draft.end.isAfter(draft.start)) {
      throw ArgumentError('Invalid review period.');
    }
    final id = const Uuid().v4();
    await _database.into(_database.reviews).insert(
          ReviewsCompanion.insert(
            id: Value(id),
            periodType: draft.periodType,
            startDate: DateKeys.toLocalDateKey(draft.start),
            endDate: DateKeys.toLocalDateKey(draft.end),
            summaryJson: Value(jsonEncode(draft.summary.toJson())),
            wins: Value(_optional(draft.wins)),
            blockers: Value(_optional(draft.blockers)),
            nextPriorities: Value(_optional(draft.nextPriorities)),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return (_database.select(_database.reviews)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<List<ReviewEntry>> list() => (_database.select(_database.reviews)
        ..where((row) => row.deletedAt.isNull())
        ..orderBy([(row) => OrderingTerm.desc(row.startDate)]))
      .get();

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
