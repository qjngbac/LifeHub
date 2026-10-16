import 'package:flutter/material.dart';

enum FirstAidRisk { emergency, high, routine }

extension FirstAidRiskUi on FirstAidRisk {
  String get label => switch (this) {
        FirstAidRisk.emergency => '紧急',
        FirstAidRisk.high => '高风险',
        FirstAidRisk.routine => '常规',
      };

  Color get color => switch (this) {
        FirstAidRisk.emergency => const Color(0xFFB3261E),
        FirstAidRisk.high => const Color(0xFFE86A17),
        FirstAidRisk.routine => const Color(0xFF2E7D5B),
      };
}

class FirstAidSource {
  const FirstAidSource({required this.title, required this.url});

  factory FirstAidSource.fromJson(Map<String, dynamic> json) =>
      FirstAidSource(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  final String title;
  final String url;
}

class FirstAidScene {
  const FirstAidScene({
    required this.id,
    required this.name,
    required this.subEnvironments,
    required this.rank,
    required this.color,
    required this.icon,
  });

  factory FirstAidScene.fromJson(Map<String, dynamic> json) => FirstAidScene(
        id: json['id'] as String,
        name: json['name'] as String,
        subEnvironments: json['subEnvironments'] as String? ?? '',
        rank: json['rank'] as int,
        color: _hexColor(json['color'] as String),
        icon: json['icon'] as String,
      );

  final String id;
  final String name;
  final String subEnvironments;
  final int rank;
  final Color color;
  final String icon;
}

class FirstAidItem {
  const FirstAidItem({
    required this.id,
    required this.number,
    required this.sceneId,
    required this.question,
    required this.answer,
    required this.steps,
    required this.fallback,
    required this.prohibitions,
    required this.risk,
  });

  factory FirstAidItem.fromJson(Map<String, dynamic> json) => FirstAidItem(
        id: json['id'] as String,
        number: json['number'] as int,
        sceneId: json['sceneId'] as String,
        question: json['question'] as String,
        answer: json['answer'] as String,
        steps: json['steps'] as String,
        fallback: json['fallback'] as String,
        prohibitions: json['prohibitions'] as String,
        risk: switch (json['risk']) {
          'EMERGENCY' => FirstAidRisk.emergency,
          'HIGH' => FirstAidRisk.high,
          _ => FirstAidRisk.routine,
        },
      );

  final String id;
  final int number;
  final String sceneId;
  final String question;
  final String answer;
  final String steps;
  final String fallback;
  final String prohibitions;
  final FirstAidRisk risk;

  bool matches(String query) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return true;
    return [question, answer, steps, fallback, prohibitions]
        .any((value) => value.toLowerCase().contains(term));
  }
}

class FirstAidKnowledge {
  const FirstAidKnowledge({
    required this.notice,
    required this.reviewedAt,
    required this.sources,
    required this.scenes,
    required this.items,
  });

  final String notice;
  final String reviewedAt;
  final List<FirstAidSource> sources;
  final List<FirstAidScene> scenes;
  final List<FirstAidItem> items;

  FirstAidScene? sceneById(String id) {
    for (final scene in scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// 场景在列表里的展示顺序（按 rank），用于把搜索结果也按场景归类排序。
  int sceneRank(String sceneId) => sceneById(sceneId)?.rank ?? 1 << 20;

  Map<FirstAidRisk, int> get riskCounts {
    final counts = <FirstAidRisk, int>{
      FirstAidRisk.emergency: 0,
      FirstAidRisk.high: 0,
      FirstAidRisk.routine: 0,
    };
    for (final item in items) {
      counts[item.risk] = (counts[item.risk] ?? 0) + 1;
    }
    return counts;
  }
}

Color _hexColor(String value) {
  final hex = value.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

IconData firstAidIcon(String name) => switch (name) {
      'apartment' => Icons.apartment,
      'park' => Icons.park,
      'agriculture' => Icons.agriculture,
      'landscape' => Icons.landscape,
      'terrain' => Icons.terrain,
      'forest' => Icons.forest,
      'eco' => Icons.eco,
      'grass' => Icons.grass,
      'wb_sunny' => Icons.wb_sunny,
      'travel_explore' => Icons.travel_explore,
      'ac_unit' => Icons.ac_unit,
      'water' => Icons.water,
      'waves' => Icons.waves,
      'beach_access' => Icons.beach_access,
      'sailing' => Icons.sailing,
      'cave' => Icons.hiking,
      'water_drop' => Icons.water_drop,
      'warning' => Icons.warning_amber_rounded,
      _ => Icons.medical_services_outlined,
    };
