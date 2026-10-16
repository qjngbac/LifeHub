import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

class NoteMetadata {
  const NoteMetadata({
    this.isPinned = false,
    this.colorHex,
    this.fontSize,
  });

  final bool isPinned;
  final String? colorHex;
  final double? fontSize;

  static NoteMetadata fromSourceUri(String? sourceUri) {
    if (sourceUri == null || sourceUri.trim().isEmpty) {
      return const NoteMetadata();
    }
    try {
      if (sourceUri.startsWith('{') && sourceUri.endsWith('}')) {
        final decoded = jsonDecode(sourceUri) as Map<String, dynamic>;
        return NoteMetadata(
          isPinned: decoded['pinned'] == true,
          colorHex: decoded['color'] as String?,
          fontSize: (decoded['fontSize'] as num?)?.toDouble(),
        );
      }
    } catch (_) {}
    return const NoteMetadata();
  }

  String toSourceUri() {
    return jsonEncode({
      'pinned': isPinned,
      if (colorHex != null) 'color': colorHex,
      if (fontSize != null) 'fontSize': fontSize,
    });
  }

  NoteMetadata copyWith({
    bool? isPinned,
    String? colorHex,
    double? fontSize,
    bool clearColor = false,
  }) {
    return NoteMetadata(
      isPinned: isPinned ?? this.isPinned,
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

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
    await _database
        .into(_database.savedItems)
        .insert(
          SavedItemsCompanion.insert(
            id: Value(id),
            title: title,
            itemType: Value(draft.itemType),
            content: Value(_contentBody(draft.content)),
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
    await (_database.update(
      _database.savedItems,
    )..where((row) => row.id.equals(id))).write(
      SavedItemsCompanion(
        title: Value(_title(draft.title)),
        itemType: Value(draft.itemType),
        content: Value(_contentBody(draft.content)),
        sourceUri: Value(_optional(draft.sourceUri)),
        associationType: Value(_optional(draft.associationType)),
        associationId: Value(_optional(draft.associationId)),
        sensitive: Value(draft.sensitive),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
    return get(id);
  }

  Future<SavedItemEntry> get(String id) async {
    final value = await (_database.select(
      _database.savedItems,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (value == null) throw StateError('Saved item not found: $id');
    return value;
  }

  Future<List<SavedItemEntry>> list({bool archived = false}) =>
      (_database.select(_database.savedItems)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.status.equals(
                    archived
                        ? SavedItemStatus.archived
                        : SavedItemStatus.active,
                  ),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .get();

  Future<List<SavedItemEntry>> search(String query) {
    final value = query.trim();
    if (value.isEmpty) return list();
    final pattern = '%${_escapeLike(value)}%';
    return (_database.select(_database.savedItems)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.status.equals(SavedItemStatus.active) &
                (row.title.like(pattern, escapeChar: r'\') |
                    row.content.like(pattern, escapeChar: r'\')),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
  }

  /// 与课程（学业）模块关联的资料 ID 集合。
  ///
  /// 课程材料虽存在 saved_items 表里，但不属于个人便签 / 收藏，
  /// 列表查询都要把它们排除掉。
  Future<Set<String>> _courseLinkedSavedItemIds() async {
    final courseLinkRows = await (_database.select(_database.entityLinks)
          ..where((row) =>
              (row.sourceType.equals('COURSE') & row.targetType.equals('SAVED_ITEM')) |
              (row.targetType.equals('COURSE') & row.sourceType.equals('SAVED_ITEM'))))
        .get();
    return <String>{
      for (final link in courseLinkRows)
        link.sourceType == 'SAVED_ITEM' ? link.sourceId : link.targetId,
    };
  }

  /// Retrieves standalone personal notes, strictly excluding:
  /// 1. Course materials from Academic/Course module (associationType: COURSE or linked via entity_links)
  /// 2. Converted entries from Inbox (associationType: INBOX or convertedId in inbox_items)
  /// 3. Any external entity associations
  Future<List<SavedItemEntry>> listNotes({
    String? query,
    String? tag,
    bool pinnedOnly = false,
    bool includeArchived = false,
    bool archivedOnly = false,
  }) async {
    // 1. Fetch course-linked saved item IDs
    final courseLinkedIds = await _courseLinkedSavedItemIds();

    // 2. Fetch inbox-converted saved item IDs
    final inboxRows = await (_database.select(_database.inboxItems)
          ..where((row) =>
              row.convertedType.equals('SAVED_ITEM') &
              row.convertedId.isNotNull()))
        .get();
    final inboxConvertedIds = <String>{
      for (final row in inboxRows)
        if (row.convertedId != null) row.convertedId!,
    };

    // 3. Query pure notes
    final q = query?.trim() ?? '';
    final pattern = q.isNotEmpty ? '%${_escapeLike(q)}%' : null;

    final queryBuilder = _database.select(_database.savedItems)
      ..where((row) {
        var expr = row.deletedAt.isNull() &
            row.itemType.equals(SavedItemType.note) &
            row.associationType.isNull(); // Exclude any explicit association

        if (archivedOnly) {
          expr = expr & row.status.equals(SavedItemStatus.archived);
        } else if (!includeArchived) {
          expr = expr & row.status.equals(SavedItemStatus.active);
        }
        if (pattern != null) {
          expr = expr &
              (row.title.like(pattern, escapeChar: r'\') |
                  row.content.like(pattern, escapeChar: r'\'));
        }
        return expr;
      });

    final allRows = await queryBuilder.get();

    // 4. In-memory filter out items that are linked to Course or Inbox
    var filtered = allRows.where((row) {
      if (courseLinkedIds.contains(row.id)) return false;
      if (inboxConvertedIds.contains(row.id)) return false;
      return true;
    }).toList();

    // 5. Filter by tag if specified
    if (tag != null && tag.isNotEmpty && tag != '全部' && tag != 'ALL') {
      final matchedIds = <String>{};
      for (final item in filtered) {
        final tags = await tagsFor(item.id);
        if (tags.any((t) => t.name.toLowerCase() == tag.toLowerCase())) {
          matchedIds.add(item.id);
        }
      }
      filtered = filtered.where((item) => matchedIds.contains(item.id)).toList();
    }

    // 6. Filter by pinned if requested
    if (pinnedOnly) {
      filtered = filtered.where((item) {
        final meta = NoteMetadata.fromSourceUri(item.sourceUri);
        return meta.isPinned;
      }).toList();
    }

    // 7. Sort: Pinned first, then by updatedAt DESC
    filtered.sort((a, b) {
      final metaA = NoteMetadata.fromSourceUri(a.sourceUri);
      final metaB = NoteMetadata.fromSourceUri(b.sourceUri);
      if (metaA.isPinned != metaB.isPinned) {
        return metaA.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return filtered;
  }

  /// 收藏（非便签类资料）列表：链接、文章、图片、文档。
  ///
  /// 这些条目此前在 App 内没有任何列表入口——全局快速新增的"收藏"存进来的
  /// 链接会变成孤儿数据；这里给它们一个家（课程资料仍排除在外）。
  ///
  /// 注意：课程关联**必须**在 Dart 侧过滤。若写成 SQL 的
  /// `NOT (associationType = 'COURSE')`，三值逻辑下会把
  /// `associationType IS NULL` 的普通收藏也一起排除掉。
  Future<List<SavedItemEntry>> listCollectibles({
    bool includeArchived = false,
  }) async {
    final courseLinkedIds = await _courseLinkedSavedItemIds();
    final builder = _database.select(_database.savedItems)
      ..where((row) {
        var expr = row.deletedAt.isNull() &
            row.itemType.isNotIn([SavedItemType.note]);
        if (!includeArchived) {
          expr = expr & row.status.equals(SavedItemStatus.active);
        }
        return expr;
      })
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    final rows = await builder.get();
    return rows
        .where((row) => row.associationType != 'COURSE')
        .where((row) => !courseLinkedIds.contains(row.id))
        .toList();
  }

  /// 只改收藏的标题 / 内容，保留 itemType、来源、关联与私密标记。
  Future<SavedItemEntry> updateCollectible(
    String id, {
    required String title,
    String? content,
  }) async {
    final item = await get(id);
    return update(
      id,
      SavedItemDraft(
        title: title,
        itemType: item.itemType,
        content: content,
        sourceUri: item.sourceUri,
        associationType: item.associationType,
        associationId: item.associationId,
        sensitive: item.sensitive,
      ),
    );
  }

  Future<SavedItemEntry> togglePin(String id) async {
    final item = await get(id);
    final currentMeta = NoteMetadata.fromSourceUri(item.sourceUri);
    return _writeMeta(id, currentMeta.copyWith(isPinned: !currentMeta.isPinned));
  }

  Future<SavedItemEntry> updateNoteColor(String id, String? colorHex) async {
    final item = await get(id);
    final currentMeta = NoteMetadata.fromSourceUri(item.sourceUri);
    return _writeMeta(
      id,
      currentMeta.copyWith(
        colorHex: colorHex,
        clearColor: colorHex == null,
      ),
    );
  }

  /// 只改写便签的展示元信息（置顶 / 纸色 / 字号），**刻意不刷新 `updatedAt`**。
  ///
  /// 置顶、换纸色、调字号都属于"怎么看"而不是"内容变了"，
  /// 若顺带把更新时间刷成当前，列表上的"3天前"立刻变"刚刚"，
  /// 排序与时间语义都会失真；同时也避免顺手把正文首尾空白 trim 掉。
  Future<SavedItemEntry> _writeMeta(String id, NoteMetadata meta) async {
    final current = await get(id);
    await (_database.update(
      _database.savedItems,
    )..where((row) => row.id.equals(id))).write(
      SavedItemsCompanion(
        sourceUri: Value(meta.toSourceUri()),
        version: Value(current.version + 1),
      ),
    );
    return get(id);
  }

  Future<List<TagEntry>> tagsFor(String id) async {
    final links =
        await (_database.select(_database.entityTags)..where(
              (row) =>
                  row.entityType.equals('SAVED_ITEM') & row.entityId.equals(id),
            ))
            .get();
    if (links.isEmpty) return const [];
    final ids = links.map((value) => value.tagId).toList();
    return (_database.select(_database.tags)
          ..where((row) => row.deletedAt.isNull() & row.id.isIn(ids))
          ..orderBy([(row) => OrderingTerm(expression: row.name)]))
        .get();
  }

  /// 一次性批量取回多条便签的标签，返回 id → 标签列表。
  ///
  /// 便签列表页原先对每条便签各查一次标签（N+1），
  /// 搜索框每敲一下都会把整页重算一遍，条目一多就明显卡顿。
  Future<Map<String, List<TagEntry>>> tagsForMany(Iterable<String> ids) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final links = await (_database.select(_database.entityTags)..where(
          (row) =>
              row.entityType.equals('SAVED_ITEM') & row.entityId.isIn(idList),
        ))
        .get();
    if (links.isEmpty) return const {};
    final tagIds = links.map((value) => value.tagId).toSet().toList();
    final tagRows = await (_database.select(_database.tags)
          ..where((row) => row.deletedAt.isNull() & row.id.isIn(tagIds))
          ..orderBy([(row) => OrderingTerm(expression: row.name)]))
        .get();
    final tagById = {for (final tag in tagRows) tag.id: tag};
    final result = <String, List<TagEntry>>{};
    for (final link in links) {
      final tag = tagById[link.tagId];
      if (tag == null) continue;
      (result[link.entityId] ??= <TagEntry>[]).add(tag);
    }
    return result;
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
      final allTags = await (_database.select(
        _database.tags,
      )..where((row) => row.deletedAt.isNull())).get();
      final byName = {for (final tag in allTags) tag.name.toLowerCase(): tag};
      final tags = <TagEntry>[];
      const colors = ['#8B79C6', '#6F9ACD', '#69A995', '#D68B83', '#C38ABB'];
      for (final name in normalized) {
        var tag = byName[name.toLowerCase()];
        if (tag == null) {
          await _database
              .into(_database.tags)
              .insert(
                TagsCompanion.insert(
                  name: name,
                  color: Value(colors[tags.length % colors.length]),
                ),
              );
          tag =
              await (_database.select(_database.tags)..where(
                    (row) => row.deletedAt.isNull() & row.name.equals(name),
                  ))
                  .getSingle();
          byName[name.toLowerCase()] = tag;
        }
        tags.add(tag);
      }
      await (_database.delete(_database.entityTags)..where(
            (row) =>
                row.entityType.equals('SAVED_ITEM') & row.entityId.equals(id),
          ))
          .go();
      for (final tag in tags) {
        await _database
            .into(_database.entityTags)
            .insert(
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
    await (_database.update(
      _database.savedItems,
    )..where((row) => row.id.equals(id))).write(
      SavedItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  Future<void> _setStatus(String id, String status) async {
    final current = await get(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(
      _database.savedItems,
    )..where((row) => row.id.equals(id))).write(
      SavedItemsCompanion(
        status: Value(status),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ),
    );
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 正文专用：**只在“整段全是空白”时置空，绝不 trim 原文**。
  ///
  /// 便签正文是 Markdown 源码，首尾空行是有意义的（代码块、行尾双空格换行、
  /// 段首缩进）。若在这里 trim，用户排好的版会被吃掉。
  static String? _contentBody(String? value) {
    if (value == null) return null;
    return value.trim().isEmpty ? null : value;
  }

  static String _title(String value) {
    final title = value.trim();
    return title.isEmpty ? '标题' : title;
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
