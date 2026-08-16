import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:uuid/uuid.dart';

class HabitDraft {
  const HabitDraft({
    required this.name,
    this.scheduleRule = 'DAILY',
    this.targetCount = 1,
    this.unit = '次',
    this.reminderPolicy,
  });

  final String name;
  final String scheduleRule;
  final int targetCount;
  final String unit;
  final String? reminderPolicy;
}

class HabitRepository {
  HabitRepository(this._database);

  final AppDatabase _database;

  Future<HabitEntry> create(HabitDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Habit name is required.');
    }
    if (draft.targetCount < 1) {
      throw ArgumentError.value(draft.targetCount, 'targetCount');
    }
    HabitRules.weeklyTarget(draft.scheduleRule);
    if (draft.reminderPolicy != null) {
      final parts = draft.reminderPolicy!.split(':');
      final hour = parts.length == 2 ? int.tryParse(parts.first) : null;
      final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
      if (hour == null ||
          minute == null ||
          hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        throw ArgumentError.value(draft.reminderPolicy, 'reminderPolicy');
      }
    }
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.habits).insert(
            HabitsCompanion.insert(
              id: Value(id),
              name: name,
              scheduleRule: Value(draft.scheduleRule),
              targetCount: Value(draft.targetCount),
              unit: Value(draft.unit.trim().isEmpty ? '次' : draft.unit.trim()),
              reminderPolicy: Value(draft.reminderPolicy),
            ),
          );
      await _log('HABIT', id, 'CREATE');
    });
    return get(id);
  }

  Future<HabitEntry> get(String id) async {
    final value = await (_database.select(_database.habits)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('Habit not found: $id');
    return value;
  }

  Future<HabitEntry> update(String id, HabitDraft draft) async {
    final current = await get(id);
    final name = draft.name.trim();
    if (name.isEmpty || draft.targetCount < 1) {
      throw ArgumentError('Habit name and target are required.');
    }
    HabitRules.weeklyTarget(draft.scheduleRule);
    _validateReminder(draft.reminderPolicy);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.habits)
            ..where((row) => row.id.equals(id)))
          .write(HabitsCompanion(
        name: Value(name),
        scheduleRule: Value(draft.scheduleRule),
        targetCount: Value(draft.targetCount),
        unit: Value(draft.unit.trim().isEmpty ? '次' : draft.unit.trim()),
        reminderPolicy: Value(draft.reminderPolicy),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('HABIT', id, 'UPDATE');
    });
    return get(id);
  }

  Future<List<HabitEntry>> list({bool activeOnly = true}) {
    final query = _database.select(_database.habits)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (activeOnly) filter = filter & row.active.equals(true);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.get();
  }

  Stream<List<HabitEntry>> watch() {
    final query = _database.select(_database.habits)
      ..where((row) => row.deletedAt.isNull() & row.active.equals(true))
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.watch();
  }

  Future<void> checkIn(
    String habitId,
    DateTime date, {
    int value = 1,
  }) async {
    await get(habitId);
    if (value < 0) throw ArgumentError.value(value, 'value');
    final localDate = DateKeys.toLocalDateKey(date);
    final existing = await (_database.select(_database.habitLogs)
          ..where((row) =>
              row.habitId.equals(habitId) & row.localDate.equals(localDate)))
        .getSingleOrNull();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      if (existing == null) {
        final id = const Uuid().v4();
        await _database.into(_database.habitLogs).insert(
              HabitLogsCompanion.insert(
                id: Value(id),
                habitId: habitId,
                localDate: localDate,
                value: Value(value),
                status: Value(value > 0 ? 'DONE' : 'SKIPPED'),
              ),
            );
        await _log('HABIT_LOG', id, 'CREATE');
      } else {
        await (_database.update(_database.habitLogs)
              ..where((row) => row.id.equals(existing.id)))
            .write(HabitLogsCompanion(
          value: Value(value),
          status: Value(value > 0 ? 'DONE' : 'SKIPPED'),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ));
        await _log('HABIT_LOG', existing.id, 'UPDATE');
      }
    });
  }

  Future<List<HabitLogEntry>> logs(String habitId) {
    final query = _database.select(_database.habitLogs)
      ..where((row) => row.habitId.equals(habitId) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.localDate)]);
    return query.get();
  }

  Future<Map<String, HabitLogEntry>> logsForDate(DateTime date) async {
    final key = DateKeys.toLocalDateKey(date);
    final values = await (_database.select(_database.habitLogs)
          ..where((row) => row.localDate.equals(key) & row.deletedAt.isNull()))
        .get();
    return {for (final value in values) value.habitId: value};
  }

  Future<int> streak(String habitId, DateTime endingOn) async {
    final habit = await get(habitId);
    final values = {for (final log in await logs(habitId)) log.localDate: log};
    var date = DateTime(endingOn.year, endingOn.month, endingOn.day);
    var result = 0;
    for (var checked = 0; checked < 3660; checked++) {
      if (!HabitRules.isScheduled(habit.scheduleRule, date)) {
        date = date.subtract(const Duration(days: 1));
        continue;
      }
      final log = values[DateKeys.toLocalDateKey(date)];
      if ((log?.value ?? 0) < habit.targetCount) {
        break;
      }
      result++;
      date = date.subtract(const Duration(days: 1));
    }
    return result;
  }

  Future<double> weeklyProgress(String habitId, DateTime withinWeek) async {
    final habit = await get(habitId);
    final day = DateTime(withinWeek.year, withinWeek.month, withinWeek.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final allLogs = await logs(habitId);
    final completed = allLogs.where((log) {
      final date = DateKeys.fromLocalDateKey(log.localDate);
      return !date.isBefore(monday) &&
          !date.isAfter(sunday) &&
          log.value >= habit.targetCount;
    }).length;
    final target = HabitRules.weeklyTarget(habit.scheduleRule);
    return (completed / target).clamp(0.0, 1.0);
  }

  Future<void> archive(String habitId) async {
    final habit = await get(habitId);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.habits)
            ..where((row) => row.id.equals(habitId)))
          .write(HabitsCompanion(
        active: const Value(false),
        updatedAt: Value(now),
        version: Value(habit.version + 1),
      ));
      await _log('HABIT', habitId, 'UPDATE');
    });
  }

  Future<void> restore(String habitId) async {
    final habit = await get(habitId);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.habits)
            ..where((row) => row.id.equals(habitId)))
          .write(HabitsCompanion(
        active: const Value(true),
        updatedAt: Value(now),
        version: Value(habit.version + 1),
      ));
      await _log('HABIT', habitId, 'RESTORE');
    });
  }

  Future<void> delete(String habitId) async {
    final habit = await get(habitId);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.habits)
            ..where((row) => row.id.equals(habitId)))
          .write(HabitsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(habit.version + 1),
      ));
      await _log('HABIT', habitId, 'DELETE');
    });
  }

  Future<void> _log(String type, String id, String operation) {
    return _database.into(_database.changeLogs).insert(
          ChangeLogsCompanion.insert(
            entityType: type,
            entityId: id,
            operation: operation,
          ),
        );
  }

  static void _validateReminder(String? value) {
    if (value == null) return;
    final parts = value.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts.first) : null;
    final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw ArgumentError.value(value, 'reminderPolicy');
    }
  }
}
