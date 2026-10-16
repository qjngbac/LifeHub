import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:lifehub/features/entertainment/domain/entertainment_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntertainmentRepository {
  // 具名参数不用 `this._preferences`：私有具名参数属于实验特性，
  // 会让 flutter analyze 报 experiment / undefined_named_parameter。
  EntertainmentRepository({
    AssetBundle? bundle,
    SharedPreferences? preferences,
    Random? random,
  })  : _bundle = bundle ?? rootBundle,
        // ignore: prefer_initializing_formals
        _preferences = preferences,
        _random = random ?? Random();

  final AssetBundle _bundle;
  SharedPreferences? _preferences;
  final Random _random;
  EntertainmentLibrary? _cache;

  static const _favoriteKey = 'entertainment.favorite_ids';
  static const _blockedKey = 'entertainment.blocked_ids';
  static const _deferredKey = 'entertainment.deferred_ids';
  static const _historyKey = 'entertainment.history_ids';

  /// "最近读过"的窗口：随机队列里把这段窗口内的条目压到最后。
  static const _recentWindow = 20;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<EntertainmentLibrary> load() async {
    if (_cache != null) return _cache!;
    final raw = await _bundle.loadString(
      'assets/content/entertainment/content.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return _cache = EntertainmentLibrary(
      categories: (json['categories'] as List)
          .cast<Map<String, dynamic>>()
          .map(EntertainmentCategory.fromJson)
          .toList(),
      items: (json['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(EntertainmentItem.fromJson)
          .toList(),
    );
  }

  Future<Set<String>> favorites() async =>
      (await _prefs).getStringList(_favoriteKey)?.toSet() ?? {};
  Future<Set<String>> blocked() async =>
      (await _prefs).getStringList(_blockedKey)?.toSet() ?? {};
  Future<Set<String>> deferred() async =>
      (await _prefs).getStringList(_deferredKey)?.toSet() ?? {};

  /// 已读历史（最近读过的在前，最多 100 条）。
  Future<List<String>> history() async =>
      (await _prefs).getStringList(_historyKey) ?? <String>[];

  /// 被屏蔽的条目，供"屏蔽管理"页恢复。
  ///
  /// 屏蔽是全局过滤（[visibleItems] 会剔除），此前没有任何入口能看到或取消，
  /// 一旦误触就再也找不回来——这里把它变成可管理的列表。
  Future<List<EntertainmentItem>> blockedItems() async {
    final library = await load();
    final ids = await blocked();
    final items =
        library.items.where((item) => ids.contains(item.id)).toList()
          ..sort((a, b) => a.category.compareTo(b.category));
    return items;
  }

  Future<bool> toggleFavorite(String id) => _toggle(_favoriteKey, id);
  Future<bool> toggleBlocked(String id) => _toggle(_blockedKey, id);
  Future<bool> toggleDeferred(String id) => _toggle(_deferredKey, id);

  Future<bool> _toggle(String key, String id) async {
    final prefs = await _prefs;
    final values = prefs.getStringList(key)?.toSet() ?? <String>{};
    final enabled = values.add(id);
    if (!enabled) values.remove(id);
    await prefs.setStringList(key, values.toList());
    return enabled;
  }

  Future<List<EntertainmentItem>> visibleItems({
    String? categoryId,
    String query = '',
    bool favoritesOnly = false,
  }) async {
    final library = await load();
    final blockedIds = await blocked();
    final favoriteIds = favoritesOnly ? await favorites() : <String>{};
    final deferredIds = await deferred();
    final items = library.items
        .where((item) => !blockedIds.contains(item.id))
        .where((item) => categoryId == null || item.categoryId == categoryId)
        .where((item) => !favoritesOnly || favoriteIds.contains(item.id))
        .where((item) => item.matches(query))
        .toList();
    items.sort((a, b) {
      final aDeferred = deferredIds.contains(a.id) ? 1 : 0;
      final bDeferred = deferredIds.contains(b.id) ? 1 : 0;
      return aDeferred != bDeferred
          ? aDeferred.compareTo(bDeferred)
          : a.id.compareTo(b.id);
    });
    return items;
  }

  Future<EntertainmentItem?> find(String id) async {
    final library = await load();
    for (final item in library.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<EntertainmentItem?> random({String? group}) async {
    final sequence = await randomSequence(group: group);
    if (sequence.isEmpty) return null;
    final recent = (await _prefs)
            .getStringList(_historyKey)
            ?.take(_recentWindow)
            .toSet() ??
        const <String>{};
    final candidates =
        sequence.where((item) => !recent.contains(item.id)).toList();
    final pool = candidates.isEmpty ? sequence : candidates;
    final item = pool[_random.nextInt(pool.length)];
    await recordViewed(item.id);
    return item;
  }

  /// 随机序列：一次给出整条可连续浏览的队列（详情页"下一条"用）。
  ///
  /// [group] 按分组过滤（笑话 / 故事 / 氛围）；[contentTypes] 按内容类型过滤，
  /// 用于把"随机故事"真正覆盖到睡前、治愈、悬疑、微小说这些氛围类故事。
  ///
  /// 队列顺序（三段稳定拼接）：
  /// 1. 普通条目（随机打散）；2. 标记"稍后再看"的条目；3. 最近读过的条目。
  /// 把最近读过的压到最后，是为了让"随机"不会立刻又抽到刚看完的那条
  /// （此前 [history] 只写不读，随机入口完全依赖打散，连点两次可能出同一条）。
  Future<List<EntertainmentItem>> randomSequence({
    String? group,
    Set<String>? contentTypes,
  }) async {
    final items = await visibleItems();
    final filtered = items
        .where((item) => group == null || item.group == group)
        .where(
          (item) =>
              contentTypes == null || contentTypes.contains(item.contentType),
        )
        .toList();
    final deferredIds = await deferred();
    final ordinary =
        filtered.where((item) => !deferredIds.contains(item.id)).toList()
          ..shuffle(_random);
    final later =
        filtered.where((item) => deferredIds.contains(item.id)).toList()
          ..shuffle(_random);
    final sequence = [...ordinary, ...later];

    final recent = (await _prefs)
            .getStringList(_historyKey)
            ?.take(_recentWindow)
            .toSet() ??
        const <String>{};
    if (recent.isEmpty) return sequence;

    final fresh = <EntertainmentItem>[];
    final seen = <EntertainmentItem>[];
    for (final item in sequence) {
      (recent.contains(item.id) ? seen : fresh).add(item);
    }
    return [...fresh, ...seen];
  }

  Future<void> recordViewed(String id) async {
    final prefs = await _prefs;
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    history.remove(id);
    history.insert(0, id);
    await prefs.setStringList(_historyKey, history.take(100).toList());
  }
}
