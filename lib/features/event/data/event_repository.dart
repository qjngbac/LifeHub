import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/event/domain/recurrence.dart';
import 'package:uuid/uuid.dart';

class EventDraft {
  const EventDraft({
    required this.title,
    required this.start,
    required this.end,
    this.eventType = 'LIFE',
    this.allDay = false,
    this.localDate,
    this.location,
    this.notes,
    this.repeatRule,
    this.projectId,
    this.preparationMinutes = 0,
    this.travelMinutes = 0,
    this.departureReminderEnabled = false,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String eventType;
  final bool allDay;
  final int? localDate;
  final String? location;
  final String? notes;
  final String? repeatRule;
  final String? projectId;
  final int preparationMinutes;
  final int travelMinutes;
  final bool departureReminderEnabled;
}

class EventOccurrence {
  const EventOccurrence({
    required this.id,
    required this.event,
    required this.start,
    required this.end,
  });

  final String id;
  final EventEntry event;
  final DateTime start;
  final DateTime end;
}

class EventRepository {
  EventRepository(this._database);

  final AppDatabase _database;

  Future<EventEntry> create(EventDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(draft.title, 'title');
    }
    if (!draft.end.isAfter(draft.start)) {
      throw ArgumentError('Event end must be after its start.');
    }
    if (draft.allDay && draft.localDate == null) {
      throw ArgumentError('All-day event requires a local date.');
    }
    _validateDeparture(draft);
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.events).insert(
            EventsCompanion.insert(
              id: Value(id),
              title: title,
              eventType: Value(draft.eventType),
              startAt: draft.start.toUtc().millisecondsSinceEpoch,
              endAt: draft.end.toUtc().millisecondsSinceEpoch,
              allDay: Value(draft.allDay),
              localDate: Value(draft.localDate),
              location: Value(_trimmedOrNull(draft.location)),
              notes: Value(_trimmedOrNull(draft.notes)),
              repeatRule: Value(draft.repeatRule),
              projectId: Value(draft.projectId),
              preparationMinutes: Value(draft.preparationMinutes),
              travelMinutes: Value(draft.travelMinutes),
              departureReminderEnabled:
                  Value(draft.departureReminderEnabled && !draft.allDay),
            ),
          );
      await _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'EVENT',
              entityId: id,
              operation: 'CREATE',
            ),
          );
    });
    return (_database.select(_database.events)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<EventEntry> get(String id) async {
    final event = await (_database.select(_database.events)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (event == null) throw StateError('Event not found: $id');
    return event;
  }

  Future<EventEntry> update(String id, EventDraft draft) async {
    final current = await get(id);
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError.value(draft.title, 'title');
    if (!draft.end.isAfter(draft.start)) {
      throw ArgumentError('Event end must be after its start.');
    }
    if (draft.allDay && draft.localDate == null) {
      throw ArgumentError('All-day event requires a local date.');
    }
    _validateDeparture(draft);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.events)
            ..where((row) => row.id.equals(id)))
          .write(EventsCompanion(
        title: Value(title),
        eventType: Value(draft.eventType),
        startAt: Value(draft.start.toUtc().millisecondsSinceEpoch),
        endAt: Value(draft.end.toUtc().millisecondsSinceEpoch),
        allDay: Value(draft.allDay),
        localDate: Value(draft.localDate),
        location: Value(_trimmedOrNull(draft.location)),
        notes: Value(_trimmedOrNull(draft.notes)),
        repeatRule: Value(draft.repeatRule),
        projectId: Value(draft.projectId),
        preparationMinutes: Value(draft.preparationMinutes),
        travelMinutes: Value(draft.travelMinutes),
        departureReminderEnabled:
            Value(draft.departureReminderEnabled && !draft.allDay),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'UPDATE');
    });
    return get(id);
  }

  Future<void> archive(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.events)
            ..where((row) => row.id.equals(id)))
          .write(EventsCompanion(
        archived: const Value(true),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'ARCHIVE');
    });
  }

  Future<List<EventEntry>> listArchived() {
    final query = _database.select(_database.events)
      ..where(
        (row) => row.deletedAt.isNull() & row.archived.equals(true),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return query.get();
  }

  Future<void> restore(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.events)
            ..where((row) => row.id.equals(id)))
          .write(EventsCompanion(
        deletedAt: const Value(null),
        archived: const Value(false),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'RESTORE');
    });
  }

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.events)
            ..where((row) => row.id.equals(id)))
          .write(EventsCompanion(
        archived: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log(id, 'DELETE');
    });
  }

  Future<List<EventEntry>> listWindow(DateTime start, DateTime end) {
    if (!end.isAfter(start)) {
      throw ArgumentError('Window end must be after its start.');
    }
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final query = _database.select(_database.events)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.archived.equals(false) &
            row.startAt.isSmallerThanValue(endMs) &
            row.endAt.isBiggerThanValue(startMs),
      )
      ..orderBy([(row) => OrderingTerm(expression: row.startAt)]);
    return query.get();
  }

  Stream<List<EventEntry>> watchWindow(DateTime start, DateTime end) {
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;
    final query = _database.select(_database.events)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.archived.equals(false) &
            row.startAt.isSmallerThanValue(endMs) &
            row.endAt.isBiggerThanValue(startMs),
      )
      ..orderBy([(row) => OrderingTerm(expression: row.startAt)]);
    return query.watch();
  }

  Future<List<EventOccurrence>> occurrencesWindow(
    DateTime start,
    DateTime end,
  ) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('Invalid event window.');
    }
    final events = await (_database.select(_database.events)
          ..where(
            (row) => row.deletedAt.isNull() & row.archived.equals(false),
          ))
        .get();
    final result = <EventOccurrence>[];
    for (final event in events) {
      final sourceStart = event.allDay && event.localDate != null
          ? DateKeys.fromLocalDateKey(event.localDate!)
          : DateTime.fromMillisecondsSinceEpoch(
              event.startAt,
              isUtc: true,
            ).toLocal();
      final storedDuration =
          Duration(milliseconds: event.endAt - event.startAt);
      final sourceEnd = event.allDay
          ? sourceStart.add(Duration(
              days: storedDuration.inHours ~/ 24 < 1
                  ? 1
                  : storedDuration.inHours ~/ 24,
            ))
          : DateTime.fromMillisecondsSinceEpoch(
              event.endAt,
              isUtc: true,
            ).toLocal();
      final duration = sourceEnd.difference(sourceStart);
      if (event.repeatRule == null) {
        if (sourceStart.isBefore(end) && sourceEnd.isAfter(start)) {
          result.add(EventOccurrence(
            id: event.id,
            event: event,
            start: sourceStart,
            end: sourceEnd,
          ));
        }
        continue;
      }
      final starts = Recurrence.expandStarts(
        sourceStart: sourceStart,
        rule: event.repeatRule,
        windowStart: start.subtract(duration),
        windowEnd: end,
      );
      for (final occurrenceStart in starts) {
        final occurrenceEnd = occurrenceStart.add(duration);
        if (occurrenceStart.isBefore(end) && occurrenceEnd.isAfter(start)) {
          result.add(EventOccurrence(
            id: '${event.id}:${occurrenceStart.toUtc().millisecondsSinceEpoch}',
            event: event,
            start: occurrenceStart,
            end: occurrenceEnd,
          ));
        }
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static void _validateDeparture(EventDraft draft) {
    if (draft.preparationMinutes < 0 || draft.travelMinutes < 0) {
      throw ArgumentError('Departure durations cannot be negative.');
    }
  }

  Future<void> _log(String id, String operation) =>
      _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'EVENT',
              entityId: id,
              operation: operation,
            ),
          );
}
