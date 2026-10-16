import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lifehub/features/first_aid/domain/first_aid_models.dart';

class FirstAidRepository {
  FirstAidRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  FirstAidKnowledge? _cache;

  Future<FirstAidKnowledge> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await _bundle.loadString(
      'assets/content/first_aid/knowledge.json',
    );
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final knowledge = FirstAidKnowledge(
      notice: json['notice'] as String,
      reviewedAt: json['reviewedAt'] as String,
      sources: (json['sources'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(FirstAidSource.fromJson)
          .toList(),
      scenes: (json['scenes'] as List)
          .cast<Map<String, dynamic>>()
          .map(FirstAidScene.fromJson)
          .toList()
        ..sort((a, b) => a.rank.compareTo(b.rank)),
      items: (json['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(FirstAidItem.fromJson)
          .toList(),
    );
    _cache = knowledge;
    return knowledge;
  }

  /// 同步过滤：页面在已加载的知识库上直接筛，避免每次重建都造一个新 Future。
  ///
  /// 覆盖条目正文 + **场景名 / 适用子环境 / 条目编号**：
  /// 此前只搜正文字段，用户搜"洪水""地震""雷暴"这类词时，只能命中正文里
  /// 恰好出现该词的条目，"灾害环境"场景下其余条目全都看不到。
  static List<FirstAidItem> filter(
    FirstAidKnowledge knowledge, {
    String query = '',
    FirstAidRisk? risk,
  }) {
    final term = query.trim().toLowerCase();
    return knowledge.items.where((item) {
      if (risk != null && item.risk != risk) return false;
      if (term.isEmpty) return true;
      if (item.matches(query)) return true;
      final scene = knowledge.sceneById(item.sceneId);
      if (scene == null) return false;
      return scene.name.toLowerCase().contains(term) ||
          scene.subEnvironments.toLowerCase().contains(term) ||
          item.number.toString().contains(term);
    }).toList();
  }

  Future<List<FirstAidItem>> search(String query) async =>
      filter(await load(), query: query);

  Future<FirstAidItem?> find(String id) async {
    final knowledge = await load();
    for (final item in knowledge.items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
