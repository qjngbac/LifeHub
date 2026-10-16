import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/domain/markdown_editing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 便签模块的回归测试：写 / 删 / 改格式，以及元信息写入语义。
///
/// 这里覆盖的是用户实际反馈过的问题：
/// 1. 在加粗内容后面继续输入再退格，会把同一篇便签里**其它**加粗一起抹掉；
/// 2. 只删一个字，光标却跳到下一行；
/// 3. 全选加粗内容删除后残留 `****`，字反而没删掉；
/// 4. 在加粗块内部按回车，渲染退化成裸露的 `**`。
void main() {
  MarkdownDeletionResult del(String oldText, String newText, [int? caret]) =>
      sanitizeMarkdownDeletion(
        oldText: oldText,
        newText: newText,
        caret: caret ?? newText.length,
      );

  group('删除不得破坏无关样式块', () {
    test('删除加粗块之后的字符，同一篇便签里所有加粗都必须存活', () {
      const oldText = '**瑞幸**\n生椰拿铁8\n**库迪**\n双柚美式';
      const newText = '**瑞幸**\n生椰拿铁8\n**库迪**\n双柚美';
      final result = del(oldText, newText);

      expect(result.text, newText);
      expect(result.text, contains('**瑞幸**'));
      expect(result.text, contains('**库迪**'));
      // 光标必须停在删除处（倒数第 1 个字符之后），不能跳到下一行
      expect(result.cursor, newText.length);
    });

    test('删除加粗块内部的一个字，加粗样式保持不变', () {
      final result = del('**瑞幸**', '**瑞**', 3);
      expect(result.text, '**瑞**');
      expect(result.cursor, 3);
    });

    test('相邻两个加粗块之间删字，不得把中间的 **** 清洗掉', () {
      final result = del('**A**和**B**', '**A****B**', 5);
      expect(result.text, '**A****B**');
      expect(result.cursor, 5);
    });

    test('删除样式块之外的裸星号，按字面删除', () {
      final result = del('价格 2*3 元', '价格 23 元', 4);
      expect(result.text, '价格 23 元');
    });
  });

  group('样式块删除的边界情形', () {
    test('全选加粗内容删除后整块消失，绝不残留 ****', () {
      final result = del('**库迪**', '****');
      expect(result.text, '');
      expect(result.cursor, 0);
    });

    test('在加粗块末尾按退格（键盘删掉闭合星号）→ 删可见字并保留加粗', () {
      final result = del('**库迪**', '**库迪*', 5);
      expect(result.text, '**库**');
      expect(result.cursor, 3);
    });

    test('加粗块内只剩一个字时再删 → 整块干净清除', () {
      final result = del('**库**', '**库*', 4);
      expect(result.text, '');
      expect(result.cursor, 0);
    });

    test('斜体与删除线的同类边界行为', () {
      expect(del('*美式*', '*美式', 3).text, '*美*');
      expect(del('~~拿铁~~', '~~拿铁~', 5).text, '~~拿~~');
    });

    test('分隔符被删残缺时补回完整样式包裹', () {
      final result = del('**瑞幸**en', '*幸**en', 1);
      expect(result.text, '**幸**en');
    });
  });

  group('在样式块内换行的自动拆分', () {
    test('加粗块内按回车 → 按行重新包好，光标落在下一行正文起点', () {
      final result = splitMarkdownSpanOnLineBreak(
        oldText: '**生椰拿铁**',
        newText: '**生椰\n拿铁**',
        insertionStart: 4,
        insertedLength: 1,
      );
      expect(result, isNotNull);
      expect(result!.text, '**生椰**\n**拿铁**');
      expect(result.text[result.cursor], '拿');
    });

    test('在加粗块末尾按回车 → 收口后换行，不留悬空标记', () {
      final result = splitMarkdownSpanOnLineBreak(
        oldText: '**A**',
        newText: '**A\n**',
        insertionStart: 3,
        insertedLength: 1,
      );
      expect(result?.text, '**A**\n');
    });

    test('普通文本里的回车不做任何处理', () {
      final result = splitMarkdownSpanOnLineBreak(
        oldText: '普通文本',
        newText: '普通\n文本',
        insertionStart: 2,
        insertedLength: 1,
      );
      expect(result, isNull);
    });
  });

  group('可见字数统计', () {
    test('不把 Markdown 标记算进字数', () {
      expect(markdownCharacterCount('**库迪**'), 2);
      expect(markdownCharacterCount('# 瑞幸\n**生椰拿铁** 8'), 7);
      expect(markdownCharacterCount('   '), 0);
    });
  });

  group('便签元信息写入语义', () {
    late AppDatabase database;
    late SavedItemRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = SavedItemRepository(database);
    });
    tearDown(() => database.close());

    test('置顶 / 换纸色只改元信息，不刷新 updatedAt、也不动正文', () async {
      final note = await repository.create(
        const SavedItemDraft(title: '购物清单', content: '西红柿  鸡蛋'),
      );

      await repository.togglePin(note.id);
      await repository.updateNoteColor(note.id, '#FFF9C4');

      final after = await repository.get(note.id);
      expect(after.updatedAt, note.updatedAt,
          reason: '置顶/换色属于"怎么看"，不该把时间刷成刚刚');
      expect(after.content, '西红柿  鸡蛋', reason: '正文首尾空白不得被顺手 trim');
      final meta = NoteMetadata.fromSourceUri(after.sourceUri);
      expect(meta.isPinned, isTrue);
      expect(meta.colorHex, '#FFF9C4');
    });

    test('listNotes(archivedOnly: true) 只返回已归档便签', () async {
      final keep = await repository.create(
        const SavedItemDraft(title: '留在列表里'),
      );
      final archived = await repository.create(
        const SavedItemDraft(title: '归档我'),
      );
      await repository.archive(archived.id);

      final archivedNotes = await repository.listNotes(archivedOnly: true);
      expect(archivedNotes.map((n) => n.id).toList(), [archived.id]);

      final activeNotes = await repository.listNotes();
      expect(activeNotes.map((n) => n.id).toList(), [keep.id]);

      await repository.restore(archived.id);
      expect((await repository.listNotes()).length, 2);
      expect(await repository.listNotes(archivedOnly: true), isEmpty);
    });

    test('tagsForMany 一次批量取回每篇便签的标签', () async {
      final first = await repository.create(const SavedItemDraft(title: 'A'));
      final second = await repository.create(const SavedItemDraft(title: 'B'));
      await repository.replaceTags(first.id, ['工作', '灵感']);
      await repository.replaceTags(second.id, ['工作']);

      final map = await repository.tagsForMany([first.id, second.id]);
      expect(map[first.id]!.map((t) => t.name).toSet(), {'工作', '灵感'});
      expect(map[second.id]!.map((t) => t.name).toSet(), {'工作'});
    });

    test('正文首尾空行与缩进原样保留，不再被 trim 掉', () async {
      const body = '\n\n```dart\nvoid main() {}\n```\n  缩进行  ';
      final created = await repository.create(
        const SavedItemDraft(title: '代码便签', content: body),
      );
      expect(created.content, body, reason: '首尾空行属于排版，保存时不得吃掉');

      await repository.update(
        created.id,
        const SavedItemDraft(title: '代码便签', content: body),
      );
      expect((await repository.get(created.id)).content, body);
    });

    test('全空白正文存为空，而不是一串空白字符', () async {
      final created = await repository.create(
        const SavedItemDraft(title: '只有空行', content: '  \n \n '),
      );
      expect(created.content, isNull);
    });

    test('listCollectibles 列出非便签资料并排除课程材料', () async {
      final link = await repository.create(
        const SavedItemDraft(
          title: 'flutter.dev',
          itemType: SavedItemType.link,
          content: 'https://flutter.dev',
          sourceUri: 'https://flutter.dev',
        ),
      );
      await repository.create(
        const SavedItemDraft(title: '普通便签', itemType: SavedItemType.note),
      );
      final courseDoc = await repository.create(
        const SavedItemDraft(
          title: '课程课件',
          itemType: SavedItemType.document,
          associationType: 'COURSE',
          associationId: 'course-1',
        ),
      );
      final archived = await repository.create(
        const SavedItemDraft(
          title: '已归档链接',
          itemType: SavedItemType.link,
        ),
      );
      await repository.archive(archived.id);

      final collectibles = await repository.listCollectibles();
      expect(collectibles.map((e) => e.id), [link.id],
          reason: '便签、课程资料、已归档项都不应出现在收藏列表');

      await repository.restore(archived.id);
      expect(
        (await repository.listCollectibles()).map((e) => e.id).toSet(),
        {link.id, archived.id},
      );
      // 课程材料即使恢复后也永远不出现
      await repository.restore(courseDoc.id);
      expect(
        (await repository.listCollectibles()).map((e) => e.id),
        isNot(contains(courseDoc.id)),
      );
    });

    test('updateCollectible 只改标题与内容，保留类型 / 来源 / 私密标记', () async {
      final link = await repository.create(
        const SavedItemDraft(
          title: '旧标题',
          itemType: SavedItemType.link,
          content: 'https://example.com',
          sourceUri: 'https://example.com',
          sensitive: true,
        ),
      );
      final updated = await repository.updateCollectible(
        link.id,
        title: '新标题',
        content: 'https://example.com/updated',
      );
      expect(updated.title, '新标题');
      expect(updated.content, 'https://example.com/updated');
      expect(updated.itemType, SavedItemType.link);
      expect(updated.sourceUri, 'https://example.com');
      expect(updated.sensitive, isTrue);
    });
  });

  group('二级密码（AppLockService）', () {
    late AppLockService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = AppLockService(await SharedPreferences.getInstance());
    });

    test('未设置时 isConfigured 为 false，任何密码都无法通过', () async {
      expect(service.isConfigured, isFalse);
      expect(await service.verify('123456'), isFalse);
    });

    test('设置后可验证正确密码、拒绝错误密码，清掉后失效', () async {
      await service.setPin('135790');
      expect(service.isConfigured, isTrue);
      expect(await service.verify('135790'), isTrue);
      expect(await service.verify('000000'), isFalse);

      await service.clearPin();
      expect(service.isConfigured, isFalse);
      expect(await service.verify('135790'), isFalse);
    });

    test('相同密码在不同盐值下哈希不同（随机盐生效）', () async {
      await service.setPin('246810');
      final firstHash = service.storedPinHash;
      await service.setPin('246810');
      final secondHash = service.storedPinHash;
      expect(firstHash, isNotEmpty);
      expect(secondHash, isNotEmpty);
      expect(firstHash, isNot(secondHash), reason: '随机盐应让哈希每次都不同');
    });

    test('AppLockNotifier 的 lock() 能够立即清除临时解锁状态', () async {
      await service.setPin('135790');
      final notifier = AppLockNotifier(service);
      expect(notifier.state.configured, isTrue);
      expect(notifier.state.isUnlocked, isFalse);

      final ok = await notifier.verify('135790');
      expect(ok, isTrue);
      expect(notifier.state.isUnlocked, isTrue);

      notifier.lock();
      expect(notifier.state.isUnlocked, isFalse);
    });
  });
}
