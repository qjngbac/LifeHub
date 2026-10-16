import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';

class RelationRepository {
  RelationRepository(this._database);

  final AppDatabase _database;

  Future<void> link(
    EntityReference first,
    EntityReference second, {
    String relationType = 'RELATED',
    String? note,
  }) async {
    if (first.key == second.key) {
      throw ArgumentError('An entity cannot link to itself.');
    }
    final endpoints = [first, second]..sort((a, b) => a.key.compareTo(b.key));
    final source = endpoints.first;
    final target = endpoints.last;
    final existing = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.sourceType.equals(source.type.toUpperCase()) &
              row.sourceId.equals(source.id) &
              row.targetType.equals(target.type.toUpperCase()) &
              row.targetId.equals(target.id)))
        .getSingleOrNull();
    if (existing != null && existing.deletedAt == null) return;
    final trimmedNote = note?.trim();
    if (existing != null) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await (_database.update(_database.entityLinks)
            ..where((row) => row.id.equals(existing.id)))
          .write(EntityLinksCompanion(
        deletedAt: const Value(null),
        relationType: Value(relationType.toUpperCase()),
        note: Value(trimmedNote?.isEmpty == true ? null : trimmedNote),
        updatedAt: Value(now),
        version: Value(existing.version + 1),
      ));
      return;
    }
    await _database.into(_database.entityLinks).insert(
          EntityLinksCompanion.insert(
            sourceType: source.type.toUpperCase(),
            sourceId: source.id,
            targetType: target.type.toUpperCase(),
            targetId: target.id,
            relationType: Value(relationType.toUpperCase()),
            note: Value(trimmedNote?.isEmpty == true ? null : trimmedNote),
          ),
        );
  }

  Future<void> unlink(EntityReference first, EntityReference second) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              (((row.sourceType.equals(first.type.toUpperCase()) &
                          row.sourceId.equals(first.id)) &
                      (row.targetType.equals(second.type.toUpperCase()) &
                          row.targetId.equals(second.id))) |
                  ((row.sourceType.equals(second.type.toUpperCase()) &
                          row.sourceId.equals(second.id)) &
                      (row.targetType.equals(first.type.toUpperCase()) &
                          row.targetId.equals(first.id))))))
        .write(EntityLinksCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<List<EntityRelation>> relationsFor(EntityReference entity) async {
    final type = entity.type.toUpperCase();
    final rows = await (_database.select(_database.entityLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              ((row.sourceType.equals(type) & row.sourceId.equals(entity.id)) |
                  (row.targetType.equals(type) &
                      row.targetId.equals(entity.id))))
          ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]))
        .get();
    final result = <EntityRelation>[];
    for (final link in rows) {
      final sourceIsEntity =
          link.sourceType == type && link.sourceId == entity.id;
      final other = EntityReference(
        type: sourceIsEntity ? link.targetType : link.sourceType,
        id: sourceIsEntity ? link.targetId : link.sourceId,
      );
      final resolved = await resolveEntity(other);
      if (resolved != null) {
        result.add(EntityRelation(
          linkId: link.id,
          entity: resolved,
          relationType: link.relationType ?? 'RELATED',
          note: link.note,
        ));
      }
    }
    return result;
  }

  Future<RelatedEntity?> resolveEntity(EntityReference reference) async {
    switch (reference.type.toUpperCase()) {
      case 'TASK':
        final row = await (_database.select(_database.tasks)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      case 'EVENT':
        final row = await (_database.select(_database.events)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      case 'COURSE':
        final row = await (_database.select(_database.courses)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'GOAL':
        final row = await (_database.select(_database.goals)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'PROJECT':
        final row = await (_database.select(_database.projects)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'TRIP':
        final row = await (_database.select(_database.tripProfiles)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        if (row == null) return null;
        final project = await (_database.select(_database.projects)
              ..where((r) => r.id.equals(row.projectId)))
            .getSingleOrNull();
        return RelatedEntity(
          reference: reference,
          title: project?.name ?? '旅行',
        );
      case 'LOCATION':
        final row = await (_database.select(_database.locations)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'SAVED_ITEM':
        final row = await (_database.select(_database.savedItems)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      case 'HOUSEHOLD':
        final row = await (_database.select(_database.householdItems)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'FINANCE':
        final row = await (_database.select(_database.financeEntries)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(
                reference: reference,
                title: row.note ?? (row.direction == 'INCOME' ? '收入' : '支出'),
              );
      case 'CREDENTIAL':
        final row = await (_database.select(_database.credentialRecords)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'SUBSCRIPTION':
        final row = await (_database.select(_database.subscriptions)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.name);
      case 'MAINTENANCE':
        final row = await (_database.select(_database.maintenancePlans)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      case 'READING':
        final row = await (_database.select(_database.readingItems)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      case 'PARCEL':
        final row = await (_database.select(_database.parcels)
              ..where((r) => r.id.equals(reference.id) & r.deletedAt.isNull()))
            .getSingleOrNull();
        return row == null
            ? null
            : RelatedEntity(reference: reference, title: row.title);
      default:
        return null;
    }
  }

  Future<RelationOverviewStats> getOverviewStats() async {
    final links = await (_database.select(_database.entityLinks)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    final counts = <String, (EntityReference, int)>{};
    for (final row in links) {
      final source = EntityReference(type: row.sourceType, id: row.sourceId);
      final target = EntityReference(type: row.targetType, id: row.targetId);
      counts[source.key] = (source, (counts[source.key]?.$2 ?? 0) + 1);
      counts[target.key] = (target, (counts[target.key]?.$2 ?? 0) + 1);
    }
    final sorted = counts.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final topHubs = <HubItem>[];
    for (final item in sorted.take(3)) {
      final entity = await resolveEntity(item.$1);
      if (entity != null) {
        topHubs.add(HubItem(entity: entity, count: item.$2));
      }
    }
    return RelationOverviewStats(
      totalLinks: links.length,
      linkedEntitiesCount: counts.length,
      topHubs: topHubs,
    );
  }

  Future<List<RelatedEntity>> candidates({
    String query = '',
    String? type,
  }) async {
    final keyword = query.trim().toLowerCase();
    final targetType = type?.toUpperCase();
    final escaped = keyword
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';
    final result = <RelatedEntity>[];
    void add(String t, String id, String title) {
      result.add(
        RelatedEntity(
          reference: EntityReference(type: t, id: id),
          title: title,
        ),
      );
    }

    bool shouldInclude(String t) =>
        targetType == null || targetType == 'ALL' || targetType == t;

    if (shouldInclude('TASK')) {
      for (final row
          in await (_database.select(_database.tasks)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('TASK', row.id, row.title);
      }
    }
    if (shouldInclude('EVENT')) {
      for (final row
          in await (_database.select(_database.events)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('EVENT', row.id, row.title);
      }
    }
    if (shouldInclude('COURSE')) {
      for (final row
          in await (_database.select(_database.courses)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('COURSE', row.id, row.name);
      }
    }
    if (shouldInclude('GOAL')) {
      for (final row
          in await (_database.select(_database.goals)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('GOAL', row.id, row.name);
      }
    }
    if (shouldInclude('PROJECT')) {
      for (final row
          in await (_database.select(_database.projects)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('PROJECT', row.id, row.name);
      }
    }
    if (shouldInclude('LOCATION')) {
      for (final row
          in await (_database.select(_database.locations)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('LOCATION', row.id, row.name);
      }
    }
    if (shouldInclude('SAVED_ITEM')) {
      for (final row
          in await (_database.select(_database.savedItems)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('SAVED_ITEM', row.id, row.title);
      }
    }
    if (shouldInclude('TRIP')) {
      for (final row
          in await _database
              .customSelect(
                "SELECT t.id, COALESCE(p.name, '旅行') AS title FROM trip_profiles t "
                "LEFT JOIN projects p ON p.id = t.project_id WHERE t.deleted_at IS NULL "
                "AND COALESCE(p.name, '旅行') LIKE ? ESCAPE '\\' LIMIT 30",
                variables: [Variable.withString(pattern)],
                readsFrom: {_database.tripProfiles, _database.projects},
              )
              .get()) {
        add('TRIP', row.read<String>('id'), row.read<String>('title'));
      }
    }
    if (shouldInclude('HOUSEHOLD')) {
      for (final row
          in await (_database.select(_database.householdItems)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('HOUSEHOLD', row.id, row.name);
      }
    }
    if (shouldInclude('FINANCE')) {
      for (final row
          in await _database
              .customSelect(
                "SELECT id, COALESCE(note, CASE WHEN direction = 'INCOME' THEN '收入' ELSE '支出' END) AS title "
                "FROM finance_entries WHERE deleted_at IS NULL "
                "AND COALESCE(note, CASE WHEN direction = 'INCOME' THEN '收入' ELSE '支出' END) "
                "LIKE ? ESCAPE '\\' LIMIT 30",
                variables: [Variable.withString(pattern)],
                readsFrom: {_database.financeEntries},
              )
              .get()) {
        add('FINANCE', row.read<String>('id'), row.read<String>('title'));
      }
    }
    if (shouldInclude('CREDENTIAL')) {
      for (final row
          in await (_database.select(_database.credentialRecords)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('CREDENTIAL', row.id, row.name);
      }
    }
    if (shouldInclude('SUBSCRIPTION')) {
      for (final row
          in await (_database.select(_database.subscriptions)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.name.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('SUBSCRIPTION', row.id, row.name);
      }
    }
    if (shouldInclude('MAINTENANCE')) {
      for (final row
          in await (_database.select(_database.maintenancePlans)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('MAINTENANCE', row.id, row.title);
      }
    }
    if (shouldInclude('READING')) {
      for (final row
          in await (_database.select(_database.readingItems)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('READING', row.id, row.title);
      }
    }
    if (shouldInclude('PARCEL')) {
      for (final row
          in await (_database.select(_database.parcels)
                ..where(
                  (r) =>
                      r.deletedAt.isNull() &
                      r.title.like(pattern, escapeChar: r'\'),
                )
                ..limit(30))
              .get()) {
        add('PARCEL', row.id, row.title);
      }
    }
    return result;
  }
}

class RelationOverviewStats {
  const RelationOverviewStats({
    required this.totalLinks,
    required this.linkedEntitiesCount,
    required this.topHubs,
  });

  final int totalLinks;
  final int linkedEntitiesCount;
  final List<HubItem> topHubs;
}

class HubItem {
  const HubItem({
    required this.entity,
    required this.count,
  });

  final RelatedEntity entity;
  final int count;
}
