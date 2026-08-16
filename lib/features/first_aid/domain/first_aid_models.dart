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
    required this.scenes,
    required this.items,
  });

  final String notice;
  final String reviewedAt;
  final List<FirstAidScene> scenes;
  final List<FirstAidItem> items;
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
