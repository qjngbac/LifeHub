import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  late AppDatabase database;
  late ListRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ListRepository(database);
  });

  tearDown(() => database.close());

  test('list item check state persists and clear checked keeps others',
      () async {
    final list = await repository.createList('旅行装备');
    final first = await repository.addItem(list.id, '帐篷');
    await repository.addItem(list.id, '水壶');

    await repository.toggleItem(first.id, checked: true);
    expect((await repository.items(list.id)).first.checked, isTrue);

    await repository.clearChecked(list.id);
    final remaining = await repository.items(list.id);
    expect(remaining.map((item) => item.textValue), ['水壶']);
  });
  test('list item converts into one task and is checked', () async {
    final list = await repository.createList('准备事项');
    final item = await repository.addItem(list.id, '购买车票');

    final task = await repository.convertItemToTask(item.id);

    expect(task.title, '购买车票');
    expect((await repository.getItem(item.id)).checked, isTrue);
    expect(await TaskRepository(database).list(), hasLength(1));
  });

  test('list can be renamed, reordered and archived', () async {
    final list = await repository.createList('old');
    final first = await repository.addItem(list.id, 'first');
    final second = await repository.addItem(list.id, 'second');

    expect((await repository.renameList(list.id, 'new')).title, 'new');
    await repository.reorderItems(list.id, [second.id, first.id]);
    expect((await repository.items(list.id)).map((item) => item.textValue),
        ['second', 'first']);
    await repository.archiveList(list.id);
    expect(await repository.lists(), isEmpty);
  });

  test('shopping trip template creates a useful checklist', () async {
    final list = await repository.createFromTemplate('逛街');
    expect(
      (await repository.items(list.id)).map((item) => item.textValue),
      ['购物预算', '优惠券', '想买清单', '环保袋'],
    );
  });

  test('archived list can be restored and deleted list stays hidden', () async {
    final list = await repository.createList('周末采购');
    await repository.archiveList(list.id);
    expect((await repository.lists(includeArchived: true)).single.archived,
        isTrue);

    await repository.restoreList(list.id);
    expect((await repository.lists()).single.archived, isFalse);

    await repository.deleteList(list.id);
    expect(await repository.lists(includeArchived: true), isEmpty);
  });
}
