import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/entertainment/data/entertainment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 娱乐模块的浏览行为回归：
/// 1. 「听个故事」必须能覆盖 atmosphere 组里的睡前 / 治愈 / 悬疑 / 微小说；
/// 2. 随机队列要把"最近读过的"压到最后，不能连点两次出同一条；
/// 3. 被屏蔽的内容要有地方能看到并恢复（此前是单向门）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EntertainmentRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = EntertainmentRepository(
      bundle: _TinyLibrary(),
      preferences: await SharedPreferences.getInstance(),
      random: _ZeroRandom(),
    );
  });

  test('按内容类型随机时，睡前/悬疑等氛围组故事同样会被选中', () async {
    final stories = await repository.randomSequence(contentTypes: {'story'});
    expect(stories.map((item) => item.id).toSet(), {'b', 'c'});
    expect(
      stories.any((item) => item.group == 'atmosphere'),
      isTrue,
      reason: '睡前 / 悬疑这类故事在 atmosphere 组，只按 group 过滤会永远抽不到',
    );
  });

  test('按分组随机仍然可用（睡前组只返回睡前内容）', () async {
    final atmosphere = await repository.randomSequence(group: 'atmosphere');
    expect(atmosphere.map((item) => item.id), ['c']);
  });

  test('最近读过的条目被压到随机队列最后，避免立刻重复', () async {
    await repository.recordViewed('a');
    final sequence = await repository.randomSequence();
    expect(sequence.last.id, 'a');
  });

  test('屏蔽内容可以列出并恢复，不再是单向门', () async {
    expect(await repository.blockedItems(), isEmpty);

    await repository.toggleBlocked('b');
    expect(await repository.blockedItems(), hasLength(1));
    expect((await repository.blockedItems()).single.id, 'b');
    // 屏蔽后从正常列表消失
    expect(
      (await repository.visibleItems()).map((item) => item.id),
      isNot(contains('b')),
    );

    await repository.toggleBlocked('b');
    expect(await repository.blockedItems(), isEmpty);
    expect(
      (await repository.visibleItems()).map((item) => item.id),
      contains('b'),
    );
  });

  test('已读历史可读回（此前只写不读）', () async {
    expect(await repository.history(), isEmpty);
    await repository.recordViewed('a');
    await repository.recordViewed('b');
    expect(await repository.history(), ['b', 'a']);
  });
}

class _ZeroRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

/// 极简内容库：一条笑话、两条故事（其中一条在 atmosphere 组）、一条脑筋急转弯。
class _TinyLibrary extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'categories': [
            {'id': 'c_joke', 'name': '笑话', 'group': 'joke'},
            {'id': 'c_story', 'name': '故事', 'group': 'story'},
            {'id': 'c_calm', 'name': '睡前故事', 'group': 'atmosphere'},
          ],
          'items': [
            _item('a', 'c_joke', '笑话', 'joke', 'joke', '掐头去尾的笑话'),
            _item('b', 'c_story', '故事', 'story', 'story', '一个普通故事'),
            _item('c', 'c_calm', '睡前故事', 'atmosphere', 'story', '一个月亮故事'),
            _item('d', 'c_joke', '笑话', 'joke', 'riddle', '答案：球门'),
          ],
        }),
      ),
    ),
  );

  static Map<String, Object> _item(
    String id,
    String categoryId,
    String category,
    String group,
    String contentType,
    String body,
  ) => {
    'id': id,
    'categoryId': categoryId,
    'category': category,
    'group': group,
    'contentType': contentType,
    'title': '标题$id',
    'body': body,
    'estimatedReadSeconds': 10,
  };
}
