import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

abstract final class SavedItemType {
  static const note = 'NOTE';
  static const article = 'ARTICLE';
  static const link = 'LINK';
  static const image = 'IMAGE';
  static const document = 'DOCUMENT';

  static const values = {note, article, link, image, document};
}

abstract final class SavedItemStatus {
  static const active = 'ACTIVE';
  static const archived = 'ARCHIVED';
}

class SavedItemDraft {
  const SavedItemDraft({
    required this.title,
    this.itemType = SavedItemType.note,
    this.content,
    this.sourceUri,
    this.associationType,
    this.associationId,
    this.sensitive = false,
  });

  final String title;
  final String itemType;
  final String? content;
  final String? sourceUri;
  final String? associationType;
  final String? associationId;
  final bool sensitive;
}

class SavedItemRepository {
  SavedItemRepository(this._database);
  final AppDatabase _database;

  Future<SavedItemEntry> create(SavedItemDraft draft) async {
    final title = _title(draft.title);
    if (!SavedItemType.values.contains(draft.itemType)) {
      throw ArgumentError.value(draft.itemType, 'itemType');
    }
    if ((draft.associationType == null) != (draft.associationId == null)) {
      throw ArgumentError('Association type and id must be supplied together.');
    }
    final id = const Uuid().v4();
    await _database.into(_database.savedItems).insert(
          SavedItemsCompanion.insert(
            id: Value(id),
            title: title,
            itemType: Value(draft.itemType),
            content: Value(_optional(draft.content)),
            sourceUri: Value(_optional(draft.sourceUri)),
            associationType: Value(_optional(draft.associationType)),
            associationId: Value(_optional(draft.associationId)),
            sensitive: Value(draft.sensitive),
          ),
        );
    return get(id);
  }

  Future<SavedItemEntry> update(String id, SavedItemDraft draft) async {
    final current = await get(id);
    if (!SavedItemType.values.contains(draft.itemType)) {
      throw ArgumentError.value(draft.itemType, 'itemType');
    }
    if ((draft.associationType == null) != (draft.associationId == null)) {
      throw ArgumentError('Association type and id must be supplied together.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.savedItems)
          ..where((row) => row.id.equals(id)))
        .write(SavedItemsCompanion(
      title: Value(_title(draft.title)),
      itemType: Value(draft.itemType),
      content: Value(_optional(draft.content)),
      sourceUri: Value(_optional(draft.sourceUri)),
      associationType: Value(_optional(draft.associationType)),
      associationId: Value(_optional(draft.associationId)),
      sensitive: Value(draft.sensitive),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  Future<SavedItemEntry> get(String id) async {
    final value = await (_database.select(_database.savedItems)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('Saved item not found: $id');
    return value;
  }

  Future<List<SavedItemEntry>> list({bool archived = false}) =>
      (_database.select(_database.savedItems)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.status.equals(archived
                    ? SavedItemStatus.archived
                    : SavedItemStatus.active))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<List<SavedItemEntry>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return list();
    final pattern = '%${_escapeLike(value)}%';
    return (_database.select(_database.savedItems)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.status.equals(SavedItemStatus.active) &
              row.sensitive.equals(false) &
              (row.title.like(pattern) | row.content.like(pattern)))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  Future<List<TagEntry>> tagsFor(String id) async {
    final links = await (_database.select(_database.entityTags)
          ..where((row) =>
              row.entityType.equals('SAVED_ITEM') & row.entityId.equals(id)))
        .get();
    if (links.isEmpty) return const [];
    final ids = links.map((value) => value.tagId).toList();
    return (_database.select(_database.tags)
          ..where((row) => row.deletedAt.isNull() & row.id.isIn(ids))
          ..orderBy([(row) => OrderingTerm(expression: row.name)]))
        .get();
  }

  Future<void> replaceTags(String id, Iterable<String> names) async {
    await get(id);
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in names) {
      final name = value.trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      normalized.add(name.length > 50 ? name.substring(0, 50) : name);
    }
    await _database.transaction(() async {
      final allTags = await (_database.select(_database.tags)
            ..where((row) => row.deletedAt.isNull()))
          .get();
      final byName = {for (final tag in allTags) tag.name.toLowerCase(): tag};
      final tags = <TagEntry>[];
      const colors = ['#8B79C6', '#6F9ACD', '#69A995', '#D68B83', '#C38ABB'];
      for (final name in normalized) {
        var tag = byName[name.toLowerCase()];
        if (tag == null) {
          await _database.into(_database.tags).insert(
                TagsCompanion.insert(
                  name: name,
                  color: Value(colors[tags.length % colors.length]),
                ),
              );
          tag = await (_database.select(_database.tags)
                ..where(
                    (row) => row.deletedAt.isNull() & row.name.equals(name)))
              .getSingle();
          byName[name.toLowerCase()] = tag;
        }
        tags.add(tag);
      }
      await (_database.delete(_database.entityTags)
            ..where((row) =>
                row.entityType.equals('SAVED_ITEM') & row.entityId.equals(id)))
          .go();
      for (final tag in tags) {
        await _database.into(_database.entityTags).insert(
              EntityTagsCompanion.insert(
                entityType: 'SAVED_ITEM',
                entityId: id,
                tagId: tag.id,
              ),
            );
      }
    });
  }

  Future<void> archive(String id) => _setStatus(id, SavedItemStatus.archived);
  Future<void> restore(String id) => _setStatus(id, SavedItemStatus.active);

  Future<void> delete(String id) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.savedItems)
          ..where((row) => row.id.equals(id)))
        .write(SavedItemsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  Future<void> _setStatus(String id, String status) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.savedItems)
          ..where((row) => row.id.equals(id)))
        .write(SavedItemsCompanion(
      status: Value(status),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _title(String value) {
    final title = value.trim();
    return title.isEmpty ? '标题' : title;
  }

  static String _escapeLike(String value) =>
      value.replaceAll('%', r'\%').replaceAll('_', r'\_');
}
