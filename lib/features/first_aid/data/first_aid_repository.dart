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

  Future<List<FirstAidItem>> search(String query) async {
    final knowledge = await load();
    return knowledge.items.where((item) => item.matches(query)).toList();
  }

  Future<FirstAidItem?> find(String id) async {
    final knowledge = await load();
    for (final item in knowledge.items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
