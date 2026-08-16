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

  Future<List<RelatedEntity>> candidates({String query = ''}) async {
    final keyword = query.trim().toLowerCase();
    final result = <RelatedEntity>[];
    Future<void> add(EntityReference ref) async {
      final value = await resolveEntity(ref);
      if (value != null &&
          (keyword.isEmpty || value.title.toLowerCase().contains(keyword))) {
        result.add(value);
      }
    }

    for (final row in await (_database.select(_database.tasks)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'TASK', id: row.id));
    }
    for (final row in await (_database.select(_database.events)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'EVENT', id: row.id));
    }
    for (final row in await (_database.select(_database.courses)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'COURSE', id: row.id));
    }
    for (final row in await (_database.select(_database.goals)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'GOAL', id: row.id));
    }
    for (final row in await (_database.select(_database.projects)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'PROJECT', id: row.id));
    }
    for (final row in await (_database.select(_database.locations)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'LOCATION', id: row.id));
    }
    for (final row in await (_database.select(_database.savedItems)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'SAVED_ITEM', id: row.id));
    }
    for (final row in await (_database.select(_database.tripProfiles)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'TRIP', id: row.id));
    }
    for (final row in await (_database.select(_database.householdItems)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'HOUSEHOLD', id: row.id));
    }
    for (final row in await (_database.select(_database.financeEntries)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'FINANCE', id: row.id));
    }
    for (final row in await (_database.select(_database.credentialRecords)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'CREDENTIAL', id: row.id));
    }
    for (final row in await (_database.select(_database.subscriptions)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'SUBSCRIPTION', id: row.id));
    }
    for (final row in await (_database.select(_database.maintenancePlans)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'MAINTENANCE', id: row.id));
    }
    for (final row in await (_database.select(_database.readingItems)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'READING', id: row.id));
    }
    for (final row in await (_database.select(_database.parcels)
          ..where((r) => r.deletedAt.isNull()))
        .get()) {
      await add(EntityReference(type: 'PARCEL', id: row.id));
    }
    return result;
  }
}
