import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:lifehub/features/entertainment/domain/entertainment_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EntertainmentRepository {
  EntertainmentRepository({
    AssetBundle? bundle,
    SharedPreferences? preferences,
    Random? random,
  })  : _bundle = bundle ?? rootBundle,
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

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<EntertainmentLibrary> load() async {
    if (_cache != null) return _cache!;
    final raw =
        await _bundle.loadString('assets/content/entertainment/content.json');
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
    final filtered = await randomSequence(group: group);
    if (filtered.isEmpty) return null;
    final prefs = await _prefs;
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    final recent = history.take(20).toSet();
    final candidates =
        filtered.where((item) => !recent.contains(item.id)).toList();
    final pool = candidates.isEmpty ? filtered : candidates;
    final item = pool[_random.nextInt(pool.length)];
    await recordViewed(item.id);
    return item;
  }

  Future<List<EntertainmentItem>> randomSequence({String? group}) async {
    final items = await visibleItems();
    final filtered =
        items.where((item) => group == null || item.group == group).toList();
    filtered.shuffle(_random);
    return filtered;
  }

  Future<void> recordViewed(String id) async {
    final prefs = await _prefs;
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    history.remove(id);
    history.insert(0, id);
    await prefs.setStringList(_historyKey, history.take(100).toList());
  }
}
