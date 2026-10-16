import 'dart:convert';
import 'package:flutter/material.dart';

class FamilyMemberProfile {
  const FamilyMemberProfile({
    required this.id,
    required this.name,
    required this.stageIndex,
    required this.stageCode,
    required this.roleLabel,
    this.iconKey,
  });

  final String id;
  final String name;
  final int stageIndex;
  final String stageCode;
  final String roleLabel;
  final String? iconKey;

  static const Map<String, IconData> _iconMap = {
    'person': Icons.person,
    'child_care': Icons.child_care,
    'elderly': Icons.elderly,
    'female': Icons.female,
    'male': Icons.male,
    'face': Icons.face,
    'medical_services': Icons.medical_services,
  };

  IconData get icon {
    if (iconKey != null && _iconMap.containsKey(iconKey)) {
      return _iconMap[iconKey]!;
    }
    if (name.contains('宝宝') || roleLabel.contains('婴幼儿') || roleLabel.contains('儿童')) {
      return Icons.child_care;
    }
    if (name.contains('父') || name.contains('母') || roleLabel.contains('老') || roleLabel.contains('中老年')) {
      return Icons.elderly;
    }
    if (roleLabel.contains('孕') || roleLabel.contains('经期') || roleLabel.contains('更年期')) {
      return Icons.female;
    }
    return Icons.person;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'stageIndex': stageIndex,
        'stageCode': stageCode,
        'roleLabel': roleLabel,
        'iconKey': iconKey,
      };

  factory FamilyMemberProfile.fromJson(Map<String, dynamic> json) =>
      FamilyMemberProfile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '家庭成员',
        stageIndex: (json['stageIndex'] as num?)?.toInt() ?? 0,
        stageCode: json['stageCode'] as String? ?? '阶段 1',
        roleLabel: json['roleLabel'] as String? ?? '',
        iconKey: json['iconKey'] as String?,
      );

  static const defaultProfiles = <FamilyMemberProfile>[
    FamilyMemberProfile(
      id: 'default_self',
      name: '本人',
      stageIndex: 3,
      stageCode: '阶段 4',
      roleLabel: '青年 (18–25岁)',
      iconKey: 'person',
    ),
    FamilyMemberProfile(
      id: 'default_baby',
      name: '宝宝',
      stageIndex: 0,
      stageCode: '阶段 1',
      roleLabel: '婴幼儿 (0–3岁)',
      iconKey: 'child_care',
    ),
    FamilyMemberProfile(
      id: 'default_parents',
      name: '父母',
      stageIndex: 7,
      stageCode: '阶段 8',
      roleLabel: '老年 (65岁以上)',
      iconKey: 'elderly',
    ),
  ];

  static String encodeList(List<FamilyMemberProfile> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<FamilyMemberProfile> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return List<FamilyMemberProfile>.from(defaultProfiles);
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => FamilyMemberProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return List<FamilyMemberProfile>.from(defaultProfiles);
    }
  }
}
