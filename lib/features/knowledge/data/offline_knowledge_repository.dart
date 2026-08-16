import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lifehub/features/knowledge/domain/offline_knowledge_models.dart';

class OfflineKnowledgeRepository {
  OfflineKnowledgeRepository({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  ConsumerGuideLibrary? _consumerGuide;
  DrugInfoLibrary? _drugInfo;

  Future<ConsumerGuideLibrary> loadConsumerGuide() async {
    final cached = _consumerGuide;
    if (cached != null) return cached;
    final raw = await _bundle.loadString(
      'assets/content/consumer_guide/catalog.json',
    );
    return _consumerGuide = ConsumerGuideLibrary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<DrugInfoLibrary> loadDrugInfo() async {
    final cached = _drugInfo;
    if (cached != null) return cached;
    final raw = await _bundle.loadString(
      'assets/content/drug_info/catalog.json',
    );
    return _drugInfo = DrugInfoLibrary.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}
