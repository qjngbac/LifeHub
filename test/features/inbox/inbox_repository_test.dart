import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';

void main() {
  test('capture is stored and conversion creates one task idempotently',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = InboxRepository(database);
    final item = await repository.capture(
      ' 阅读这篇文章 ',
      sourceType: 'ANDROID_SHARE',
      sourceUri: 'https://example.com',
    );
    expect((await repository.list()).single.content, '阅读这篇文章');

    final task = await repository.convertToTask(item.id);
    final second = await repository.convertToTask(item.id);
    expect(second.id, task.id);
    expect((await TaskRepository(database).list()), hasLength(1));
    expect((await repository.get(item.id)).state, 'PROCESSED');
  });

  test('link-like inbox content converts to one saved item idempotently',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = InboxRepository(database);
    final item = await repository.capture('https://example.com/article');

    final saved = await repository.convertToSavedItem(item.id);
    final second = await repository.convertToSavedItem(item.id);

    expect(second.id, saved.id);
    expect(saved.itemType, SavedItemType.link);
    expect(await SavedItemRepository(database).list(), hasLength(1));
  });

  test('later items can convert to list items, daily events, or be retained',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = InboxRepository(database);
    final lists = ListRepository(database);
    final list = await lists.createList('采购');

    final listCapture = await repository.capture('牛奶');
    await repository.setState(listCapture.id, InboxState.later);
    final item = await repository.convertToListItem(listCapture.id, list.id);
    expect(item.textValue, '牛奶');
    expect((await repository.get(listCapture.id)).convertedType, 'LIST_ITEM');

    final eventCapture = await repository.capture('散步');
    final event = await repository.convertToDailyEvent(
      eventCapture.id,
      DateTime(2026, 8, 9),
    );
    expect(event.title, '散步');
    expect((await repository.get(eventCapture.id)).convertedType, 'LIFE_EVENT');

    final retained = await repository.capture('仅保留的笔记');
    await repository.retain(retained.id);
    expect((await repository.get(retained.id)).convertedType, 'RETAINED');
    expect(await repository.list(state: InboxState.processed), hasLength(3));
  });

  test('captured content can be edited before or after organizing', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = InboxRepository(database);
    final item = await repository.capture('原内容');

    final edited = await repository.updateContent(item.id, ' 修改后的内容 ');

    expect(edited.content, '修改后的内容');
    expect(edited.version, item.version + 1);
  });
}
