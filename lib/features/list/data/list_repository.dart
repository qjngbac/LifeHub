import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:uuid/uuid.dart';

class ListRepository {
  ListRepository(this._database);

  final AppDatabase _database;

  static const templates = <String, List<String>>{
    '购物': ['蔬菜', '水果', '日用品'],
    '逛街': ['购物预算', '优惠券', '想买清单', '环保袋'],
    '每周采购': ['主食', '蔬果', '乳制品', '清洁用品'],
    '旅行': ['证件', '充电器', '换洗衣物'],
    '露营装备': ['帐篷', '睡袋', '照明', '饮用水'],
    '搬家': ['打包箱', '胶带', '地址变更'],
    '面试准备': ['简历', '作品集', '路线确认'],
    '新生开学': ['录取材料', '宿舍用品', '校园卡', '课程安排'],
    '健身包': ['运动鞋', '毛巾', '水杯', '替换衣物'],
    '看病准备': ['身份证', '医保卡', '既往病历', '用药记录'],
  };

  Future<ListEntry> createList(String title, {String? projectId}) async {
    final value = title.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(title, 'title', 'List title is required.');
    }
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.lists).insert(
            ListsCompanion.insert(
              id: Value(id),
              title: value,
              projectId: Value(projectId),
            ),
          );
      await _log('LIST', id, 'CREATE');
    });
    return getList(id);
  }

  Future<ListEntry> createFromTemplate(String templateName) async {
    final items = templates[templateName];
    if (items == null) throw ArgumentError.value(templateName, 'templateName');
    final list = await createList(templateName);
    for (final item in items) {
      await addItem(list.id, item);
    }
    await (_database.update(_database.lists)
          ..where((row) => row.id.equals(list.id)))
        .write(const ListsCompanion(template: Value(true)));
    return getList(list.id);
  }

  Future<ListEntry> getList(String id) async {
    final value = await (_database.select(_database.lists)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('List not found: $id');
    return value;
  }

  Future<ListEntry> renameList(String id, String title) async {
    final current = await getList(id);
    final value = title.trim();
    if (value.isEmpty) throw ArgumentError.value(title, 'title');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lists)
            ..where((row) => row.id.equals(id)))
          .write(ListsCompanion(
        title: Value(value),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('LIST', id, 'UPDATE');
    });
    return getList(id);
  }

  Future<void> archiveList(String id) async {
    final current = await getList(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lists)
            ..where((row) => row.id.equals(id)))
          .write(ListsCompanion(
        archived: const Value(true),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('LIST', id, 'ARCHIVE');
    });
  }

  Future<void> restoreList(String id) async {
    final current = await getList(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lists)
            ..where((row) => row.id.equals(id)))
          .write(ListsCompanion(
        archived: const Value(false),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('LIST', id, 'RESTORE');
    });
  }

  Future<void> deleteList(String id) async {
    final current = await getList(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.lists)
            ..where((row) => row.id.equals(id)))
          .write(ListsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('LIST', id, 'DELETE');
    });
  }

  Future<List<ListEntry>> lists({bool includeArchived = false}) {
    final query = _database.select(_database.lists)
      ..where((row) {
        var filter = row.deletedAt.isNull();
        if (!includeArchived) filter = filter & row.archived.equals(false);
        return filter;
      })
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.get();
  }

  Stream<List<ListEntry>> watchLists() {
    final query = _database.select(_database.lists)
      ..where((row) => row.deletedAt.isNull() & row.archived.equals(false))
      ..orderBy([(row) => OrderingTerm(expression: row.createdAt)]);
    return query.watch();
  }

  Future<ListItemEntry> addItem(String listId, String text) async {
    await getList(listId);
    final value = text.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(text, 'text', 'List item text is required.');
    }
    final maxSort = _database.listItems.sortKey.max();
    final result = await (_database.selectOnly(_database.listItems)
          ..addColumns([maxSort])
          ..where(_database.listItems.listId.equals(listId) &
              _database.listItems.deletedAt.isNull()))
        .getSingle();
    final sortKey = (result.read(maxSort) ?? -1) + 1;
    final id = const Uuid().v4();
    await _database.transaction(() async {
      await _database.into(_database.listItems).insert(
            ListItemsCompanion.insert(
              id: Value(id),
              listId: listId,
              textValue: value,
              sortKey: Value(sortKey),
            ),
          );
      await _log('LIST_ITEM', id, 'CREATE');
    });
    return getItem(id);
  }

  Future<ListItemEntry> getItem(String id) async {
    final value = await (_database.select(_database.listItems)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('List item not found: $id');
    return value;
  }

  Future<List<ListItemEntry>> items(String listId) {
    final query = _database.select(_database.listItems)
      ..where((row) => row.listId.equals(listId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm(expression: row.sortKey),
        (row) => OrderingTerm(expression: row.createdAt),
      ]);
    return query.get();
  }

  Stream<List<ListItemEntry>> watchItems(String listId) {
    final query = _database.select(_database.listItems)
      ..where((row) => row.listId.equals(listId) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm(expression: row.sortKey)]);
    return query.watch();
  }

  Future<void> toggleItem(String id, {required bool checked}) async {
    final current = await getItem(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await (_database.update(_database.listItems)
            ..where((row) => row.id.equals(id)))
          .write(ListItemsCompanion(
        checked: Value(checked),
        updatedAt: Value(now),
        version: Value(current.version + 1),
      ));
      await _log('LIST_ITEM', id, 'UPDATE');
    });
  }

  Future<void> reorderItems(String listId, List<String> orderedIds) async {
    final current = await items(listId);
    final currentIds = current.map((item) => item.id).toSet();
    if (orderedIds.length != current.length ||
        orderedIds.toSet().length != orderedIds.length ||
        !orderedIds.every(currentIds.contains)) {
      throw ArgumentError('Ordered ids must contain every active list item.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final byId = {for (final item in current) item.id: item};
    await _database.transaction(() async {
      for (var index = 0; index < orderedIds.length; index++) {
        final item = byId[orderedIds[index]]!;
        await (_database.update(_database.listItems)
              ..where((row) => row.id.equals(item.id)))
            .write(ListItemsCompanion(
          sortKey: Value(index.toDouble()),
          updatedAt: Value(now),
          version: Value(item.version + 1),
        ));
        await _log('LIST_ITEM', item.id, 'UPDATE');
      }
    });
  }

  Future<void> clearChecked(String listId) async {
    final checked = await (_database.select(_database.listItems)
          ..where((row) =>
              row.listId.equals(listId) &
              row.checked.equals(true) &
              row.deletedAt.isNull()))
        .get();
    if (checked.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      for (final item in checked) {
        await (_database.update(_database.listItems)
              ..where((row) => row.id.equals(item.id)))
            .write(ListItemsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(item.version + 1),
        ));
        await _log('LIST_ITEM', item.id, 'DELETE');
      }
    });
  }

  Future<TaskEntry> convertItemToTask(String itemId) async {
    final item = await getItem(itemId);
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await _database.into(_database.tasks).insert(
            TasksCompanion.insert(id: Value(id), title: item.textValue),
          );
      await (_database.update(_database.listItems)
            ..where((row) => row.id.equals(item.id)))
          .write(ListItemsCompanion(
        checked: const Value(true),
        updatedAt: Value(now),
        version: Value(item.version + 1),
      ));
      await _log('TASK', id, 'CREATE');
      await _log('LIST_ITEM', item.id, 'CONVERT');
    });
    return TaskRepository(_database).get(id);
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
}
