import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/first_aid/data/first_aid_repository.dart';

class SearchResult {
  const SearchResult(
      {required this.type, required this.id, required this.title});
  final String type;
  final String id;
  final String title;
}

class SearchRepository {
  SearchRepository(
    this._database, {
    FirstAidRepository? firstAid,
  }) : _firstAid = firstAid;
  final AppDatabase _database;
  final FirstAidRepository? _firstAid;

  Future<List<SearchResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final pattern = '%${term.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final tasks = await (_database.select(_database.tasks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.title.like(pattern))
          ..limit(30))
        .get();
    final events = await (_database.select(_database.events)
          ..where((row) => row.deletedAt.isNull() & row.title.like(pattern))
          ..limit(30))
        .get();
    final projects = await (_database.select(_database.projects)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final lists = await (_database.select(_database.lists)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.archived.equals(false) &
              row.title.like(pattern))
          ..limit(30))
        .get();
    final habits = await (_database.select(_database.habits)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.active.equals(true) &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final relationships =
        await (_database.select(_database.relationshipProfiles)
              ..where((row) =>
                  row.deletedAt.isNull() &
                  row.active.equals(true) &
                  (row.name.like(pattern) | row.nickname.like(pattern)))
              ..limit(30))
            .get();
    final lifeEvents = await (_database.select(_database.lifeEvents)
          ..where((row) => row.deletedAt.isNull() & row.title.like(pattern))
          ..limit(30))
        .get();
    final anniversaries = await (_database.select(_database.anniversaries)
          ..where((row) => row.deletedAt.isNull() & row.title.like(pattern))
          ..limit(30))
        .get();
    final goals = await (_database.select(_database.goals)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final savedItems = await (_database.select(_database.savedItems)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ACTIVE') &
              row.sensitive.equals(false) &
              (row.title.like(pattern) | row.content.like(pattern)))
          ..limit(30))
        .get();
    final locations = await (_database.select(_database.locations)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ACTIVE') &
              (row.name.like(pattern) | row.address.like(pattern)))
          ..limit(30))
        .get();
    final tripProjects = await (_database.select(_database.projects)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final tripProjectIds = tripProjects.map((value) => value.id).toList();
    final trips = tripProjectIds.isEmpty
        ? <TripProfileEntry>[]
        : await (_database.select(_database.tripProfiles)
              ..where((row) =>
                  row.deletedAt.isNull() &
                  row.status.equals('ARCHIVED').not() &
                  row.projectId.isIn(tripProjectIds)))
            .get();
    final tripNames = {for (final value in tripProjects) value.id: value.name};
    final household = await (_database.select(_database.householdItems)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ARCHIVED').not() &
              row.sensitive.equals(false) &
              (row.name.like(pattern) | row.brandModel.like(pattern)))
          ..limit(30))
        .get();
    final medications = await (_database.select(_database.medicationPlans)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.active.equals(true) &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final finances = await (_database.select(_database.financeEntries)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.sensitive.equals(false) &
              row.note.like(pattern))
          ..limit(30))
        .get();
    final subscriptions = await (_database.select(_database.subscriptions)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals('ACTIVE') &
              row.name.like(pattern))
          ..limit(30))
        .get();
    final firstAid = await _firstAid?.search(term) ?? const [];
    return [
      ...tasks.map((value) =>
          SearchResult(type: 'TASK', id: value.id, title: value.title)),
      ...events.map((value) =>
          SearchResult(type: 'EVENT', id: value.id, title: value.title)),
      ...projects
          .where((value) => !trips.any((trip) => trip.projectId == value.id))
          .map((value) =>
              SearchResult(type: 'PROJECT', id: value.id, title: value.name)),
      ...lists.map((value) =>
          SearchResult(type: 'LIST', id: value.id, title: value.title)),
      ...habits.map((value) =>
          SearchResult(type: 'HABIT', id: value.id, title: value.name)),
      ...relationships.map((value) => SearchResult(
            type: 'RELATIONSHIP',
            id: value.id,
            title: value.name,
          )),
      ...lifeEvents.map((value) => SearchResult(
            type: 'LIFE_EVENT',
            id: value.id,
            title: value.title,
          )),
      ...anniversaries.map((value) => SearchResult(
            type: 'ANNIVERSARY',
            id: value.id,
            title: value.title,
          )),
      ...goals.map((value) =>
          SearchResult(type: 'GOAL', id: value.id, title: value.name)),
      ...savedItems.map((value) => SearchResult(
            type: 'SAVED_ITEM',
            id: value.id,
            title: value.title,
          )),
      ...locations.map((value) => SearchResult(
            type: 'LOCATION',
            id: value.id,
            title: value.name,
          )),
      ...trips.map((value) => SearchResult(
            type: 'TRIP',
            id: value.id,
            title: tripNames[value.projectId] ?? '旅行',
          )),
      ...household.map((value) => SearchResult(
            type: 'HOUSEHOLD',
            id: value.id,
            title: value.name,
          )),
      ...medications.map((value) => SearchResult(
            type: 'MEDICATION',
            id: value.id,
            title: value.name,
          )),
      ...finances.map((value) => SearchResult(
            type: 'FINANCE',
            id: value.id,
            title: value.note ?? '收支记录',
          )),
      ...subscriptions.map((value) => SearchResult(
            type: 'SUBSCRIPTION',
            id: value.id,
            title: value.name,
          )),
      ...firstAid.map((value) => SearchResult(
            type: 'FIRST_AID',
            id: value.id,
            title: value.question,
          )),
    ];
  }
}
