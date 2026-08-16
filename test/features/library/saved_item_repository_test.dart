import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';

void main() {
  late AppDatabase database;
  late SavedItemRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = SavedItemRepository(database);
  });
  tearDown(() => database.close());

  test('creates typed saved items and searches title or content', () async {
    await repository.create(const SavedItemDraft(
      title: '登山装备攻略',
      itemType: SavedItemType.article,
      content: '记得携带冲锋衣',
      sourceUri: 'https://example.com/hiking',
      associationType: 'PROJECT',
      associationId: 'outdoor-plan',
    ));

    final results = await repository.search('冲锋衣');
    expect(results.single.title, '登山装备攻略');
    expect(results.single.itemType, SavedItemType.article);
    expect(results.single.associationId, 'outdoor-plan');
  });

  test('archive hides item and restore makes it visible', () async {
    final item = await repository.create(
      const SavedItemDraft(title: '灵感', itemType: SavedItemType.note),
    );
    await repository.archive(item.id);
    expect(await repository.list(), isEmpty);
    expect(await repository.list(archived: true), hasLength(1));
    await repository.restore(item.id);
    expect(await repository.list(), hasLength(1));
  });

  test('tags are normalized, reused and replaceable', () async {
    final first = await repository.create(const SavedItemDraft(title: '攻略'));
    final second = await repository.create(const SavedItemDraft(title: '清单'));

    await repository.replaceTags(first.id, ['旅行', ' 实用 ', '旅行']);
    await repository.replaceTags(second.id, ['旅行']);

    expect((await repository.tagsFor(first.id)).map((value) => value.name),
        {'旅行', '实用'});
    expect(await database.select(database.tags).get(), hasLength(2));

    await repository.replaceTags(first.id, ['稍后阅读']);
    expect((await repository.tagsFor(first.id)).single.name, '稍后阅读');
  });

  test('blank title defaults to 标题 and note content can be edited', () async {
    final item = await repository.create(
      const SavedItemDraft(title: '   ', content: '第一版'),
    );

    final updated = await repository.update(
      item.id,
      const SavedItemDraft(title: '读书摘录', content: '第二版'),
    );

    expect(item.title, '标题');
    expect(updated.title, '读书摘录');
    expect(updated.content, '第二版');
    expect(updated.createdAt, item.createdAt);
    expect(updated.version, item.version + 1);
  });
}
