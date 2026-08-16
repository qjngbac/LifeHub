import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:uuid/uuid.dart';

abstract final class InboxState {
  static const newItem = 'NEW';
  static const later = 'LATER';
  static const processed = 'PROCESSED';
  static const archived = 'ARCHIVED';
}

class InboxRepository {
  InboxRepository(this._database);
  final AppDatabase _database;

  Future<InboxItemEntry> capture(
    String content, {
    String sourceType = 'MANUAL',
    String? sourceUri,
  }) async {
    final value = content.trim();
    if (value.isEmpty) throw ArgumentError.value(content, 'content');
    final id = const Uuid().v4();
    await _database.into(_database.inboxItems).insert(
          InboxItemsCompanion.insert(
            id: Value(id),
            content: value,
            sourceType: Value(sourceType),
            sourceUri: Value(_optional(sourceUri)),
          ),
        );
    return get(id);
  }

  Future<InboxItemEntry> get(String id) async {
    final row = await (_database.select(_database.inboxItems)
          ..where((value) => value.id.equals(id)))
        .getSingleOrNull();
    if (row == null) throw StateError('Inbox item not found.');
    return row;
  }

  Future<List<InboxItemEntry>> list({
    String state = InboxState.newItem,
  }) =>
      (_database.select(_database.inboxItems)
            ..where((row) => row.deletedAt.isNull() & row.state.equals(state))
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  Future<InboxItemEntry> updateContent(String id, String content) async {
    final value = content.trim();
    if (value.isEmpty) throw ArgumentError.value(content, 'content');
    final current = await get(id);
    await (_database.update(_database.inboxItems)
          ..where((row) => row.id.equals(id)))
        .write(InboxItemsCompanion(
      content: Value(value),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
    return get(id);
  }

  Future<void> setState(String id, String state) async {
    const allowed = {
      InboxState.newItem,
      InboxState.later,
      InboxState.processed,
      InboxState.archived,
    };
    if (!allowed.contains(state)) throw ArgumentError.value(state, 'state');
    final current = await get(id);
    await (_database.update(_database.inboxItems)
          ..where((row) => row.id.equals(id)))
        .write(InboxItemsCompanion(
      state: Value(state),
      updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      version: Value(current.version + 1),
    ));
  }

  Future<TaskEntry> convertToTask(String id) => _database.transaction(() async {
        final current = await get(id);
        if (current.convertedType == 'TASK' && current.convertedId != null) {
          return TaskRepository(_database).get(current.convertedId!);
        }
        _ensureConvertible(current);
        final task = await TaskRepository(_database)
            .create(TaskDraft(title: current.content));
        await _markConverted(current, 'TASK', task.id);
        return task;
      });

  Future<SavedItemEntry> convertToSavedItem(String id) =>
      _database.transaction(() async {
        final current = await get(id);
        if (current.convertedType == 'SAVED_ITEM' &&
            current.convertedId != null) {
          return SavedItemRepository(_database).get(current.convertedId!);
        }
        _ensureConvertible(current);
        final uri = Uri.tryParse(current.content);
        final isLink = uri?.hasScheme == true;
        final saved = await SavedItemRepository(_database).create(
          SavedItemDraft(
            title: isLink && uri!.host.isNotEmpty ? uri.host : current.content,
            itemType: isLink ? SavedItemType.link : SavedItemType.note,
            content: current.content,
            sourceUri: isLink ? current.content : current.sourceUri,
          ),
        );
        await _markConverted(current, 'SAVED_ITEM', saved.id);
        return saved;
      });

  Future<ListItemEntry> convertToListItem(String id, String listId) =>
      _database.transaction(() async {
        final current = await get(id);
        if (current.convertedType == 'LIST_ITEM' &&
            current.convertedId != null) {
          return ListRepository(_database).getItem(current.convertedId!);
        }
        _ensureConvertible(current);
        await ListRepository(_database).getList(listId);
        final item = await ListRepository(_database).addItem(
          listId,
          current.content,
        );
        await _markConverted(current, 'LIST_ITEM', item.id);
        return item;
      });

  Future<LifeEventEntry> convertToDailyEvent(
    String id,
    DateTime date,
  ) =>
      _database.transaction(() async {
        final current = await get(id);
        if (current.convertedType == 'LIFE_EVENT' &&
            current.convertedId != null) {
          return LifeEventRepository(_database).get(current.convertedId!);
        }
        _ensureConvertible(current);
        final event = await LifeEventRepository(_database).create(
          LifeEventDraft(title: current.content, date: date),
        );
        await _markConverted(current, 'LIFE_EVENT', event.id);
        return event;
      });

  Future<void> retain(String id) => _database.transaction(() async {
        final current = await get(id);
        if (current.convertedType == 'RETAINED') return;
        _ensureConvertible(current);
        await _markConverted(current, 'RETAINED', current.id);
      });

  void _ensureConvertible(InboxItemEntry current) {
    if (current.convertedType != null) {
      throw StateError('收件箱内容已经整理过。');
    }
  }

  Future<void> _markConverted(
    InboxItemEntry current,
    String type,
    String id,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.inboxItems)
          ..where((row) => row.id.equals(current.id)))
        .write(InboxItemsCompanion(
      state: const Value(InboxState.processed),
      convertedType: Value(type),
      convertedId: Value(id),
      updatedAt: Value(now),
      version: Value(current.version + 1),
    ));
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
