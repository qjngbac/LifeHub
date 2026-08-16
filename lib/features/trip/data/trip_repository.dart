import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:uuid/uuid.dart';

class TripDraft {
  const TripDraft({
    required this.name,
    required this.startDate,
    required this.endDate,
    this.description,
    this.notes,
    this.color = '#8B79C6',
  });
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String? description;
  final String? notes;
  final String color;
}

class TripOverview {
  const TripOverview({
    required this.trip,
    required this.project,
    required this.tasks,
    required this.events,
    required this.lists,
    required this.lifeEvents,
    required this.locations,
    required this.expenses,
  });
  final TripProfileEntry trip;
  final ProjectEntry project;
  final List<TaskEntry> tasks;
  final List<EventEntry> events;
  final List<ListEntry> lists;
  final List<LifeEventEntry> lifeEvents;
  final List<LocationEntry> locations;
  final List<TripExpenseEntry> expenses;
}

class TripLinkCandidate {
  const TripLinkCandidate({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
  });
  final String type;
  final String id;
  final String title;
  final String? subtitle;
}

class TripRepository {
  TripRepository(this._database);
  final AppDatabase _database;

  Future<TripProfileEntry> create(TripDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError.value(draft.name, 'name');
    final start = DateKeys.toLocalDateKey(draft.startDate);
    final end = DateKeys.toLocalDateKey(draft.endDate);
    if (end < start) throw ArgumentError('Trip end date is before start date.');
    final projectId = const Uuid().v4();
    final tripId = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.projects).insert(ProjectsCompanion.insert(
            id: Value(projectId),
            name: name,
            description: Value(_optional(draft.description)),
            color: Value(draft.color),
            startAt: Value(DateTime(draft.startDate.year, draft.startDate.month,
                    draft.startDate.day)
                .toUtc()
                .millisecondsSinceEpoch),
            dueAt: Value(DateTime(draft.endDate.year, draft.endDate.month,
                    draft.endDate.day, 23, 59)
                .toUtc()
                .millisecondsSinceEpoch),
          ));
      await _database.into(_database.tripProfiles).insert(
            TripProfilesCompanion.insert(
              id: Value(tripId),
              projectId: projectId,
              startDate: start,
              endDate: end,
              notes: Value(_optional(draft.notes)),
            ),
          );
      await _database.into(_database.changeLogs).insert(
            ChangeLogsCompanion.insert(
              entityType: 'TRIP',
              entityId: tripId,
              operation: 'CREATE',
            ),
          );
    });
    return get(tripId);
  }

  Future<TripProfileEntry> get(String id) async {
    final value = await (_database.select(_database.tripProfiles)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('Trip not found: $id');
    return value;
  }

  Future<List<TripProfileEntry>> list({
    Set<String> statuses = const {'PLANNING', 'COMPLETED'},
  }) =>
      (_database.select(_database.tripProfiles)
            ..where((row) => row.deletedAt.isNull() & row.status.isIn(statuses))
            ..orderBy([(row) => OrderingTerm(expression: row.startDate)]))
          .get();

  Future<ProjectEntry> projectFor(TripProfileEntry trip) =>
      (_database.select(_database.projects)
            ..where((row) => row.id.equals(trip.projectId)))
          .getSingle();

  Future<void> link(String tripId, String targetType, String targetId) async {
    await get(tripId);
    final type = targetType.trim().toUpperCase();
    final id = targetId.trim();
    if (type.isEmpty || id.isEmpty) throw ArgumentError('Invalid trip link.');
    final existing = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sourceType.equals('TRIP') &
              row.sourceId.equals(tripId) &
              row.targetType.equals(type) &
              row.targetId.equals(id)))
        .getSingleOrNull();
    if (existing != null) return;
    await _database.into(_database.entityLinks).insert(
          EntityLinksCompanion.insert(
            sourceType: 'TRIP',
            sourceId: tripId,
            targetType: type,
            targetId: id,
          ),
        );
  }

  Future<List<TripLinkCandidate>> linkCandidates(
    String tripId,
    String targetType,
  ) async {
    final trip = await get(tripId);
    final type = targetType.toUpperCase();
    final links = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sourceType.equals('TRIP') &
              row.sourceId.equals(tripId) &
              row.targetType.equals(type)))
        .get();
    final linkedIds = links.map((link) => link.targetId).toSet();
    final start = DateKeys.fromLocalDateKey(trip.startDate)
        .toUtc()
        .millisecondsSinceEpoch;
    final end = DateKeys.fromLocalDateKey(trip.endDate)
        .add(const Duration(days: 1))
        .toUtc()
        .millisecondsSinceEpoch;
    switch (type) {
      case 'TASK':
        final rows = await (_database.select(_database.tasks)
              ..where((row) =>
                  row.deletedAt.isNull() &
                  (row.dueAt.isBetweenValues(start, end - 1) |
                      row.startAt.isBetweenValues(start, end - 1))))
            .get();
        return [
          for (final row in rows)
            if (!linkedIds.contains(row.id))
              TripLinkCandidate(type: type, id: row.id, title: row.title),
        ];
      case 'EVENT':
        final rows = await (_database.select(_database.events)
              ..where((row) =>
                  row.deletedAt.isNull() &
                  row.startAt.isBetweenValues(start, end - 1)))
            .get();
        return [
          for (final row in rows)
            if (!linkedIds.contains(row.id))
              TripLinkCandidate(
                type: type,
                id: row.id,
                title: row.title,
                subtitle: row.location,
              ),
        ];
      case 'LOCATION':
        final rows = await (_database.select(_database.locations)
              ..where((row) => row.deletedAt.isNull()))
            .get();
        return [
          for (final row in rows)
            if (!linkedIds.contains(row.id))
              TripLinkCandidate(
                type: type,
                id: row.id,
                title: row.name,
                subtitle: row.address,
              ),
        ];
      default:
        throw ArgumentError.value(targetType, 'targetType');
    }
  }

  Future<TripOverview> overview(String id) async {
    final trip = await get(id);
    final project = await projectFor(trip);
    final links = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sourceType.equals('TRIP') &
              row.sourceId.equals(id)))
        .get();
    List<String> ids(String type) => links
        .where((link) => link.targetType == type)
        .map((link) => link.targetId)
        .toList();
    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              (row.projectId.equals(project.id) | row.id.isIn(ids('TASK')))))
        .get();
    final events = await (_database.select(_database.events)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.archived.equals(false) &
              (row.projectId.equals(project.id) | row.id.isIn(ids('EVENT')))))
        .get();
    final lists = await (_database.select(_database.lists)
          ..where((row) =>
              row.deletedAt.isNull() & row.projectId.equals(project.id)))
        .get();
    final lifeEventIds = ids('LIFE_EVENT');
    final lifeEvents = lifeEventIds.isEmpty
        ? <LifeEventEntry>[]
        : await (_database.select(_database.lifeEvents)
              ..where(
                  (row) => row.deletedAt.isNull() & row.id.isIn(lifeEventIds)))
            .get();
    final locationIds = ids('LOCATION');
    final locations = locationIds.isEmpty
        ? <LocationEntry>[]
        : await (_database.select(_database.locations)
              ..where(
                  (row) => row.deletedAt.isNull() & row.id.isIn(locationIds)))
            .get();
    final expenses = await (_database.select(_database.tripExpenses)
          ..where((row) => row.deletedAt.isNull() & row.tripId.equals(id))
          ..orderBy([(row) => OrderingTerm(expression: row.expenseDate)]))
        .get();
    return TripOverview(
      trip: trip,
      project: project,
      tasks: tasks,
      events: events,
      lists: lists,
      lifeEvents: lifeEvents,
      locations: locations,
      expenses: expenses,
    );
  }

  Future<void> archive(String id) => _setStatus(id, 'ARCHIVED');
  Future<void> restore(String id) => _setStatus(id, 'PLANNING');
  Future<void> complete(String id) => _setStatus(id, 'COMPLETED');

  Future<void> savePostTripReview(String id, String? notes) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.tripProfiles)
          ..where((row) => row.id.equals(id)))
        .write(TripProfilesCompanion(
      notes: Value(_optional(notes)),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  Future<void> applyTemplate(String id, String template) async {
    final trip = await get(id);
    if (template == 'NONE') return;
    final definitions = switch (template) {
      'OUTDOOR' => (
          ['背包', '饮用水', '防晒与急救用品'],
          ['查看天气与路线', '告知紧急联系人行程'],
        ),
      _ => (
          ['身份证件', '充电器', '常用药品'],
          ['确认交通', '确认住宿'],
        ),
    };
    final listId = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.lists).insert(ListsCompanion.insert(
            id: Value(listId),
            title: '旅行装备',
            listType: const Value('TRAVEL'),
            projectId: Value(trip.projectId),
          ));
      for (var index = 0; index < definitions.$1.length; index++) {
        await _database.into(_database.listItems).insert(
              ListItemsCompanion.insert(
                listId: listId,
                textValue: definitions.$1[index],
                sortKey: Value(index.toDouble()),
              ),
            );
      }
      for (final title in definitions.$2) {
        await _database.into(_database.tasks).insert(TasksCompanion.insert(
              title: title,
              category: const Value('LIFE'),
              projectId: Value(trip.projectId),
              dueAt: Value(
                DateKeys.fromLocalDateKey(trip.startDate)
                    .subtract(const Duration(days: 1))
                    .toUtc()
                    .millisecondsSinceEpoch,
              ),
            ));
      }
    });
  }

  Future<void> delete(String id, {bool deleteProject = false}) async {
    final trip = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.tripProfiles)
            ..where((row) => row.id.equals(id)))
          .write(TripProfilesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(trip.version + 1),
      ));
      if (deleteProject) {
        await (_database.update(_database.projects)
              ..where((row) => row.id.equals(trip.projectId)))
            .write(ProjectsCompanion(deletedAt: Value(now)));
      }
    });
  }

  Future<void> _setStatus(String id, String status) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.tripProfiles)
          ..where((row) => row.id.equals(id)))
        .write(TripProfilesCompanion(
      status: Value(status),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
