import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/core/time/date_keys.dart';

class TodayEvent {
  const TodayEvent(
      {required this.id,
      required this.title,
      required this.start,
      required this.end,
      this.location,
      this.isCourse = false});
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final bool isCourse;
}

class TodayHabit {
  const TodayHabit(
      {required this.habit, required this.completed, this.value = 0});
  final HabitEntry habit;
  final bool completed;
  final int value;
}

class TodayAnniversary {
  const TodayAnniversary({required this.entry, required this.daysUntil});

  final AnniversaryEntry entry;
  final int daysUntil;
}

class TodayTrip {
  const TodayTrip({
    required this.trip,
    required this.project,
    required this.daysUntil,
  });
  final TripProfileEntry trip;
  final ProjectEntry project;
  final int daysUntil;
}

class TodayGoal {
  const TodayGoal({required this.goal, required this.progress});
  final GoalEntry goal;
  final double progress;
}

class TodaySnapshot {
  const TodaySnapshot({
    required this.tasks,
    required this.events,
    required this.habits,
    this.anniversaries = const [],
    this.trips = const [],
    this.goals = const [],
    this.focus,
  });
  final List<TaskEntry> tasks;
  final List<TodayEvent> events;
  final List<TodayHabit> habits;
  final List<TodayAnniversary> anniversaries;
  final List<TodayTrip> trips;
  final List<TodayGoal> goals;
  final FocusSessionEntry? focus;
}

class TodayService {
  TodayService(this._database);
  final AppDatabase _database;

  Future<TodaySnapshot> load(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.isNotIn(
                  [TaskStatus.done, TaskStatus.canceled, TaskStatus.archived]) &
              (row.dueAt.isBetweenValues(startMs, endMs - 1) |
                  row.startAt.isBetweenValues(startMs, endMs - 1) |
                  (row.dueAt.isNull() &
                      row.startAt.isNull() &
                      row.priority.isBiggerOrEqualValue(3))))
          ..orderBy([(row) => OrderingTerm.desc(row.dueAt)]))
        .get();
    final events =
        await EventRepository(_database).occurrencesWindow(start, end);
    final habits = (await HabitRepository(_database).list())
        .where((value) => HabitRules.isScheduled(value.scheduleRule, start))
        .toList();
    final logs = await HabitRepository(_database).logsForDate(start);
    final anniversaryRepository = AnniversaryRepository(_database);
    final anniversaries = (await anniversaryRepository.listAll())
        .where((value) => value.showInToday)
        .map((value) => TodayAnniversary(
              entry: value,
              daysUntil: anniversaryRepository.daysUntil(value, start),
            ))
        .where((value) => value.daysUntil >= 0 && value.daysUntil <= 30)
        .toList()
      ..sort((left, right) => left.daysUntil.compareTo(right.daysUntil));
    final goalRows = await (_database.select(_database.goals)
          ..where((row) =>
              row.deletedAt.isNull() & row.status.equals(GoalStatus.active))
          ..orderBy([
            (row) => OrderingTerm(
                  expression: row.targetAt,
                  nulls: NullsOrder.last,
                ),
          ])
          ..limit(3))
        .get();
    final goalRepository = GoalRepository(_database);
    final goals = <TodayGoal>[];
    for (final goal in goalRows) {
      goals.add(TodayGoal(
        goal: goal,
        progress: await goalRepository.progress(goal.id),
      ));
    }
    final focus = await FocusRepository(_database).active();
    final todayKey = DateKeys.toLocalDateKey(start);
    final limitKey =
        DateKeys.toLocalDateKey(start.add(const Duration(days: 30)));
    final tripRows = await (_database.select(_database.tripProfiles)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('PLANNING') &
              row.startDate.isBetweenValues(todayKey, limitKey))
          ..orderBy([(row) => OrderingTerm(expression: row.startDate)]))
        .get();
    final trips = <TodayTrip>[];
    for (final trip in tripRows) {
      final project = await (_database.select(_database.projects)
            ..where((row) =>
                row.id.equals(trip.projectId) & row.deletedAt.isNull()))
          .getSingleOrNull();
      if (project == null) continue;
      trips.add(TodayTrip(
        trip: trip,
        project: project,
        daysUntil:
            DateKeys.fromLocalDateKey(trip.startDate).difference(start).inDays,
      ));
    }
    final mergedEvents = events
        .map((value) => TodayEvent(
              id: value.id,
              title: value.event.title,
              start: value.start,
              end: value.end,
              location: value.event.location,
            ))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return TodaySnapshot(
      tasks: tasks,
      events: mergedEvents,
      habits: habits.map((habit) {
        final log = logs[habit.id];
        return TodayHabit(
          habit: habit,
          completed: (log?.value ?? 0) >= habit.targetCount,
          value: log?.value ?? 0,
        );
      }).toList(),
      anniversaries: anniversaries,
      trips: trips,
      goals: goals,
      focus: focus,
    );
  }
}
