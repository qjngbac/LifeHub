import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/focus/application/focus_clock.dart';
import 'package:uuid/uuid.dart';

abstract final class FocusStatus {
  static const running = 'RUNNING';
  static const paused = 'PAUSED';
  static const finished = 'FINISHED';
  static const discarded = 'DISCARDED';
}

abstract final class FocusMode {
  static const countdown = 'COUNTDOWN';
  static const stopwatch = 'STOPWATCH';
}

class FocusDraft {
  const FocusDraft({
    required this.plannedMinutes,
    this.mode = FocusMode.countdown,
    this.entityType,
    this.entityId,
    this.note,
  });

  final int plannedMinutes;
  final String mode;
  final String? entityType;
  final String? entityId;
  final String? note;
}

class FocusRepository {
  FocusRepository(this._database);
  final AppDatabase _database;

  Future<FocusSessionEntry> start(
    FocusDraft draft, {
    DateTime? now,
  }) async {
    if (!const {FocusMode.countdown, FocusMode.stopwatch}
        .contains(draft.mode)) {
      throw ArgumentError.value(draft.mode, 'mode');
    }
    final invalidCountdown = draft.mode == FocusMode.countdown &&
        (draft.plannedMinutes < 1 || draft.plannedMinutes > 1440);
    final invalidStopwatch =
        draft.mode == FocusMode.stopwatch && draft.plannedMinutes != 0;
    if (invalidCountdown || invalidStopwatch) {
      throw ArgumentError.value(draft.plannedMinutes, 'plannedMinutes');
    }
    final id = const Uuid().v4();
    await _database.transaction(() async {
      if (await active() != null) {
        throw StateError('A focus session is already active.');
      }
      await _database.into(_database.focusSessions).insert(
            FocusSessionsCompanion.insert(
              id: Value(id),
              mode: Value(draft.mode),
              plannedMinutes: draft.plannedMinutes,
              startedAt: (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
              entityType: Value(draft.entityType),
              entityId: Value(draft.entityId),
              note: Value(_optional(draft.note)),
            ),
          );
    });
    return get(id);
  }

  Future<FocusSessionEntry?> active() =>
      (_database.select(_database.focusSessions)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.status.isIn([FocusStatus.running, FocusStatus.paused]))
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<FocusSessionEntry> get(String id) async {
    final row = await (_database.select(_database.focusSessions)
          ..where((value) => value.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Focus session not found.');
    return row;
  }

  Future<FocusSessionEntry> pause(String id, {DateTime? now}) async {
    final current = await get(id);
    if (current.status != FocusStatus.running) {
      throw StateError('Only a running session can pause.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _write(
      current,
      FocusSessionsCompanion(
        status: const Value(FocusStatus.paused),
        pausedAt: Value(timestamp),
      ),
    );
    return get(id);
  }

  Future<FocusSessionEntry> resume(String id, {DateTime? now}) async {
    final current = await get(id);
    if (current.status != FocusStatus.paused || current.pausedAt == null) {
      throw StateError('Only a paused session can resume.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final totalPaused = current.pausedMillis + timestamp - current.pausedAt!;
    await _write(
      current,
      FocusSessionsCompanion(
        status: const Value(FocusStatus.running),
        pausedAt: const Value(null),
        pausedMillis: Value(totalPaused),
      ),
    );
    return get(id);
  }

  Future<FocusSessionEntry> finish(String id, {DateTime? now}) async {
    var current = await get(id);
    final end = (now ?? DateTime.now()).toUtc();
    if (current.status == FocusStatus.paused && current.pausedAt != null) {
      final totalPaused =
          current.pausedMillis + end.millisecondsSinceEpoch - current.pausedAt!;
      await _write(
        current,
        FocusSessionsCompanion(
          pausedAt: const Value(null),
          pausedMillis: Value(totalPaused),
        ),
      );
      current = await get(id);
    }
    if (current.status != FocusStatus.running &&
        current.status != FocusStatus.paused) {
      throw StateError('Session is not active.');
    }
    final minutes = FocusClock.elapsed(current, end).inMinutes;
    await _write(
      current,
      FocusSessionsCompanion(
        status: const Value(FocusStatus.finished),
        endedAt: Value(end.millisecondsSinceEpoch),
        pausedAt: const Value(null),
        actualMinutes: Value(minutes),
      ),
    );
    return get(id);
  }

  Future<FocusSessionEntry?> finishIfDue(
    String id, {
    DateTime? now,
  }) async {
    final current = await get(id);
    if (current.status == FocusStatus.finished) return current;
    if (current.status != FocusStatus.running) return null;
    if (current.mode == FocusMode.stopwatch) return null;
    final deadline = DateTime.fromMillisecondsSinceEpoch(
      current.startedAt +
          current.pausedMillis +
          Duration(minutes: current.plannedMinutes).inMilliseconds,
      isUtc: true,
    );
    if ((now ?? DateTime.now()).toUtc().isBefore(deadline)) return null;
    try {
      return await finish(id, now: deadline);
    } on StateError {
      final latest = await get(id);
      return latest.status == FocusStatus.finished ? latest : null;
    }
  }

  Future<void> discard(String id) async {
    final current = await get(id);
    await _write(
      current,
      FocusSessionsCompanion(
        status: const Value(FocusStatus.discarded),
        deletedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      ),
    );
  }

  Future<List<FocusSessionEntry>> finishedBetween(
    DateTime start,
    DateTime end,
  ) =>
      (_database.select(_database.focusSessions)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.status.equals(FocusStatus.finished) &
                row.endedAt.isBiggerOrEqualValue(
                    start.toUtc().millisecondsSinceEpoch) &
                row.endedAt
                    .isSmallerThanValue(end.toUtc().millisecondsSinceEpoch)))
          .get();

  Future<void> _write(
    FocusSessionEntry current,
    FocusSessionsCompanion changes,
  ) async {
    await (_database.update(_database.focusSessions)
          ..where((row) => row.id.equals(current.id)))
        .write(changes.copyWith(
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
