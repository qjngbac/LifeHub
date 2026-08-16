import 'package:flutter/material.dart';

class MoodOption {
  const MoodOption({
    required this.code,
    required this.label,
    required this.emoji,
    required this.color,
  });

  final String code;
  final String label;
  final String emoji;
  final Color color;
}

abstract final class MoodCatalog {
  static const happy = 'HAPPY';
  static const joyful = 'JOYFUL';
  static const calm = 'CALM';
  static const hopeful = 'HOPEFUL';
  static const tired = 'TIRED';
  static const anxious = 'ANXIOUS';
  static const low = 'LOW';
  static const irritated = 'IRRITATED';
  static const angry = 'ANGRY';
  static const sad = 'SAD';

  static const values = <MoodOption>[
    MoodOption(
      code: happy,
      label: '开心',
      emoji: '😊',
      color: Color(0xFFFFD166),
    ),
    MoodOption(
      code: joyful,
      label: '兴奋',
      emoji: '🥳',
      color: Color(0xFFFFB86B),
    ),
    MoodOption(
      code: calm,
      label: '平静',
      emoji: '😌',
      color: Color(0xFFA8DADC),
    ),
    MoodOption(
      code: hopeful,
      label: '期待',
      emoji: '🥰',
      color: Color(0xFFCDB4DB),
    ),
    MoodOption(
      code: tired,
      label: '疲惫',
      emoji: '😫',
      color: Color(0xFFB8C0D9),
    ),
    MoodOption(
      code: anxious,
      label: '焦虑',
      emoji: '😟',
      color: Color(0xFF9EC5E6),
    ),
    MoodOption(
      code: low,
      label: '低落',
      emoji: '😔',
      color: Color(0xFFB8B8D1),
    ),
    MoodOption(
      code: irritated,
      label: '烦躁',
      emoji: '😣',
      color: Color(0xFFF4A6A6),
    ),
    MoodOption(
      code: angry,
      label: '生气',
      emoji: '😠',
      color: Color(0xFFEF7D7D),
    ),
    MoodOption(
      code: sad,
      label: '难过',
      emoji: '😢',
      color: Color(0xFF8FB5D9),
    ),
  ];

  static MoodOption option(String code) => values.firstWhere(
        (value) => value.code == code,
        orElse: () => throw ArgumentError.value(code, 'code'),
      );

  static bool contains(String code) =>
      values.any((value) => value.code == code);

  static String label(String code) => option(code).label;

  static String emoji(String code) => option(code).emoji;

  static Color color(String code) => option(code).color;
}
