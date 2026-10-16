class LifecycleCatalog {
  const LifecycleCatalog({
    required this.version,
    required this.stages,
    required this.fruits,
    required this.vegetables,
    required this.seasonCalendar,
    required this.foodTopics,
    required this.envTopics,
    required this.drugInteractions,
    required this.rumors,
    required this.replacementSchedule,
    required this.checkupSchedule,
    required this.exercisePrescriptions,
    required this.commonPitfalls,
  });

  factory LifecycleCatalog.fromJson(Map<String, dynamic> json) {
    return LifecycleCatalog(
      version: json['version'] as String? ?? '1.10.0',
      stages: (json['stages'] as List<dynamic>? ?? [])
          .map((e) => LifecycleStage.fromJson(e as Map<String, dynamic>))
          .toList(),
      fruits: (json['fruits'] as List<dynamic>? ?? [])
          .map((e) => FruitItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      vegetables: (json['vegetables'] as List<dynamic>? ?? [])
          .map((e) => VegetableItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      seasonCalendar: (json['seasonCalendar'] as List<dynamic>? ?? [])
          .map((e) => SeasonCalendarItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      foodTopics: (json['foodTopics'] as List<dynamic>? ?? [])
          .map((e) => KnowledgeTopic.fromJson(e as Map<String, dynamic>))
          .toList(),
      envTopics: (json['envTopics'] as List<dynamic>? ?? [])
          .map((e) => KnowledgeTopic.fromJson(e as Map<String, dynamic>))
          .toList(),
      drugInteractions: (json['drugInteractions'] as List<dynamic>? ?? [])
          .map((e) => DrugInteractionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      rumors: (json['rumors'] as List<dynamic>? ?? [])
          .map((e) => RumorItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      replacementSchedule: (json['replacementSchedule'] as List<dynamic>? ?? [])
          .map((e) =>
              ReplacementScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      checkupSchedule: (json['checkupSchedule'] as List<dynamic>? ?? [])
          .map((e) => CheckupScheduleItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      exercisePrescriptions:
          (json['exercisePrescriptions'] as List<dynamic>? ?? [])
              .map((e) => KnowledgeTopic.fromJson(e as Map<String, dynamic>))
              .toList(),
      commonPitfalls: (json['commonPitfalls'] as List<dynamic>? ?? [])
          .cast<String>(),
    );
  }

  final String version;
  final List<LifecycleStage> stages;
  final List<FruitItem> fruits;
  final List<VegetableItem> vegetables;
  final List<SeasonCalendarItem> seasonCalendar;
  final List<KnowledgeTopic> foodTopics;
  final List<KnowledgeTopic> envTopics;
  final List<DrugInteractionItem> drugInteractions;
  final List<RumorItem> rumors;
  final List<ReplacementScheduleItem> replacementSchedule;
  final List<CheckupScheduleItem> checkupSchedule;
  final List<KnowledgeTopic> exercisePrescriptions;
  final List<String> commonPitfalls;

  List<LifecycleSearchResult> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final results = <LifecycleSearchResult>[];

    // Search fruits
    for (final f in fruits) {
      if (f.matches(q)) {
        results.add(LifecycleSearchResult(
          id: f.id,
          sourceBadge: '水果图鉴 · ${f.category}',
          title: f.name,
          subtitle: '应季：${f.season} | 热量：${f.calories}',
          summary: f.tips.isNotEmpty ? f.tips : f.nutrition,
          alertLevel: f.alertLevel,
          warningText: f.precautions,
          tags: f.tags,
          details: [
            if (f.season.isNotEmpty) '【应季时期】${f.season}',
            if (f.calories.isNotEmpty) '【热量参考】${f.calories}',
            if (f.nutrition.isNotEmpty) '【主要营养】${f.nutrition}',
            if (f.specialComponent.isNotEmpty) '【特色成分】${f.specialComponent}',
            if (f.tips.isNotEmpty) '【吃法建议】${f.tips}',
            if (f.precautions.isNotEmpty) '【注意事项】${f.precautions}',
          ].join('\n\n'),
        ));
      }
    }

    // Search vegetables
    for (final v in vegetables) {
      if (v.matches(q)) {
        results.add(LifecycleSearchResult(
          id: v.id,
          sourceBadge: '蔬菜图鉴 · ${v.category}',
          title: v.name,
          subtitle: '主要营养：${v.nutrition}',
          summary: v.cookingAdvice.isNotEmpty ? v.cookingAdvice : v.specialPhyto,
          alertLevel: v.alertLevel,
          warningText: v.precautions,
          tags: v.tags,
          details: [
            if (v.nutrition.isNotEmpty) '【主要营养】${v.nutrition}',
            if (v.specialPhyto.isNotEmpty) '【特色植化素】${v.specialPhyto}',
            if (v.oxalatePurinePotassium.isNotEmpty)
              '【草酸/嘌呤/钾】${v.oxalatePurinePotassium}',
            if (v.cookingAdvice.isNotEmpty) '【烹饪建议】${v.cookingAdvice}',
            if (v.precautions.isNotEmpty) '【注意事项】${v.precautions}',
          ].join('\n\n'),
        ));
      }
    }

    // Search drug interactions
    for (var i = 0; i < drugInteractions.length; i++) {
      final item = drugInteractions[i];
      if (item.matches(q)) {
        results.add(LifecycleSearchResult(
          id: 'drug_inter_$i',
          sourceBadge: '药物禁忌 · ${item.source}',
          title: '${item.drugCategory} ✕ ${item.avoidFood}',
          subtitle: '需避开：${item.avoidFood}',
          summary: item.mechanism,
          alertLevel: item.alertLevel,
          warningText: item.mechanism,
          tags: const ['药物相互作用', '🚨禁忌'],
          details: '【药物类别】${item.drugCategory}\n\n'
              '【避开食物/补充剂】${item.avoidFood}\n\n'
              '【机制与后果】${item.mechanism}\n\n'
              '【出处与依据】${item.source}',
        ));
      }
    }

    // Search environment topics
    for (final t in envTopics) {
      if (t.matches(q)) {
        results.add(LifecycleSearchResult(
          id: t.id,
          sourceBadge: '日用环境 · ${t.category}',
          title: t.title,
          subtitle: t.category,
          summary: t.bullets.isNotEmpty ? t.bullets.first : '',
          alertLevel: t.alertLevel,
          tags: [t.category],
          details: t.bullets.map((b) => '• $b').join('\n'),
        ));
      }
    }

    // Search stages
    for (final s in stages) {
      if (s.matches(q)) {
        results.add(LifecycleSearchResult(
          id: s.id,
          sourceBadge: '人生阶段 · ${s.codeLabel}',
          title: s.name,
          subtitle: s.codeLabel,
          summary: s.redlines.isNotEmpty ? s.redlines.first : '',
          alertLevel: s.redlines.isNotEmpty ? 'warning' : 'none',
          tags: [s.codeLabel],
          details: [
            if (s.redlines.isNotEmpty)
              '【核心安全红线】\n${s.redlines.map((r) => '• $r').join('\n')}',
            for (final sub in s.subsections)
              '【${sub.title}】\n${sub.bullets.map((b) => '• $b').join('\n')}',
          ].join('\n\n'),
        ));
      }
    }

    // Search rumors
    for (final r in rumors) {
      if (r.matches(q)) {
        results.add(LifecycleSearchResult(
          id: 'rumor_${r.id}',
          sourceBadge: '辟谣清单 · 科学真相',
          title: r.claim,
          subtitle: '科学真相辟谣',
          summary: r.truth,
          alertLevel: 'warning',
          tags: const ['辟谣', '科学真相'],
          details: '【流传说法】${r.claim}\n\n【科学真相】${r.truth}',
        ));
      }
    }

    // Search food topics
    for (final t in foodTopics) {
      if (t.matches(q)) {
        results.add(LifecycleSearchResult(
          id: t.id,
          sourceBadge: '食物指南 · ${t.category}',
          title: t.title,
          subtitle: t.category,
          summary: t.subsections.isNotEmpty &&
                  t.subsections.first.bullets.isNotEmpty
              ? t.subsections.first.bullets.first
              : '',
          alertLevel: 'none',
          tags: [t.category],
          details: t.subsections
              .map((sub) =>
                  '【${sub.title}】\n${sub.bullets.map((b) => '• $b').join('\n')}')
              .join('\n\n'),
        ));
      }
    }

    // Search checkups
    for (var i = 0; i < checkupSchedule.length; i++) {
      final c = checkupSchedule[i];
      if (c.matches(q)) {
        results.add(LifecycleSearchResult(
          id: 'checkup_$i',
          sourceBadge: '体检筛查时间表',
          title: c.item,
          subtitle: '${c.frequency} | 适用：${c.target}',
          summary: c.notes.isNotEmpty ? c.notes : c.frequency,
          alertLevel: 'none',
          tags: const ['体检', '健康筛查'],
          details: '【检查项目】${c.item}\n\n'
              '【建议频率】${c.frequency}\n\n'
              '【适用人群】${c.target}\n\n'
              '【注意事项】${c.notes}',
        ));
      }
    }

    // Search exercise prescriptions
    for (final ex in exercisePrescriptions) {
      if (ex.matches(q)) {
        results.add(LifecycleSearchResult(
          id: ex.id,
          sourceBadge: '运动处方 · ${ex.category}',
          title: ex.title,
          subtitle: ex.category,
          summary: ex.bullets.isNotEmpty ? ex.bullets.first : '',
          alertLevel: ex.alertLevel,
          tags: const ['运动处方', '健身', '健康干预'],
          details: [
            for (final b in ex.bullets) '• $b',
            for (final tbl in ex.tables)
              for (final r in tbl)
                r.entries.map((e) => '${e.key}：${e.value}').join(' | '),
          ].join('\n\n'),
        ));
      }
    }

    return results;
  }
}

class LifecycleStage {
  const LifecycleStage({
    required this.id,
    required this.rawTitle,
    required this.codeLabel,
    required this.name,
    required this.subsections,
    required this.redlines,
  });

  factory LifecycleStage.fromJson(Map<String, dynamic> json) => LifecycleStage(
        id: json['id'] as String? ?? '',
        rawTitle: json['rawTitle'] as String? ?? '',
        codeLabel: json['codeLabel'] as String? ?? '',
        name: json['name'] as String? ?? '',
        subsections: (json['subsections'] as List<dynamic>? ?? [])
            .map((e) =>
                KnowledgeSubsection.fromJson(e as Map<String, dynamic>))
            .toList(),
        redlines: (json['redlines'] as List<dynamic>? ?? []).cast<String>(),
      );

  final String id;
  final String rawTitle;
  final String codeLabel;
  final String name;
  final List<KnowledgeSubsection> subsections;
  final List<String> redlines;

  bool matches(String q) {
    if (rawTitle.toLowerCase().contains(q) ||
        codeLabel.toLowerCase().contains(q) ||
        name.toLowerCase().contains(q)) {
      return true;
    }
    for (final r in redlines) {
      if (r.toLowerCase().contains(q)) return true;
    }
    for (final s in subsections) {
      if (s.matches(q)) return true;
    }
    return false;
  }
}

class FruitItem {
  const FruitItem({
    required this.id,
    required this.category,
    required this.name,
    required this.season,
    required this.calories,
    required this.nutrition,
    required this.specialComponent,
    required this.tips,
    required this.precautions,
    required this.alertLevel,
    required this.tags,
  });

  factory FruitItem.fromJson(Map<String, dynamic> json) => FruitItem(
        id: json['id'] as String? ?? '',
        category: json['category'] as String? ?? '',
        name: json['name'] as String? ?? '',
        season: json['season'] as String? ?? '',
        calories: json['calories'] as String? ?? '',
        nutrition: json['nutrition'] as String? ?? '',
        specialComponent: json['specialComponent'] as String? ?? '',
        tips: json['tips'] as String? ?? '',
        precautions: json['precautions'] as String? ?? '',
        alertLevel: json['alertLevel'] as String? ?? 'none',
        tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      );

  final String id;
  final String category;
  final String name;
  final String season;
  final String calories;
  final String nutrition;
  final String specialComponent;
  final String tips;
  final String precautions;
  final String alertLevel;
  final List<String> tags;

  bool matches(String q) {
    return name.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        season.toLowerCase().contains(q) ||
        nutrition.toLowerCase().contains(q) ||
        specialComponent.toLowerCase().contains(q) ||
        tips.toLowerCase().contains(q) ||
        precautions.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }
}

class VegetableItem {
  const VegetableItem({
    required this.id,
    required this.category,
    required this.name,
    this.calories = '',
    this.season = '',
    required this.nutrition,
    required this.specialPhyto,
    required this.oxalatePurinePotassium,
    required this.cookingAdvice,
    required this.precautions,
    required this.alertLevel,
    required this.tags,
  });

  factory VegetableItem.fromJson(Map<String, dynamic> json) => VegetableItem(
        id: json['id'] as String? ?? '',
        category: json['category'] as String? ?? '',
        name: json['name'] as String? ?? '',
        calories: json['calories'] as String? ?? '',
        season: json['season'] as String? ?? '',
        nutrition: json['nutrition'] as String? ?? '',
        specialPhyto: json['specialPhyto'] as String? ?? '',
        oxalatePurinePotassium:
            json['oxalatePurinePotassium'] as String? ?? '',
        cookingAdvice: json['cookingAdvice'] as String? ?? '',
        precautions: json['precautions'] as String? ?? '',
        alertLevel: json['alertLevel'] as String? ?? 'none',
        tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      );

  final String id;
  final String category;
  final String name;
  final String calories;
  final String season;
  final String nutrition;
  final String specialPhyto;
  final String oxalatePurinePotassium;
  final String cookingAdvice;
  final String precautions;
  final String alertLevel;
  final List<String> tags;

  bool matches(String q) {
    return name.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        nutrition.toLowerCase().contains(q) ||
        specialPhyto.toLowerCase().contains(q) ||
        oxalatePurinePotassium.toLowerCase().contains(q) ||
        cookingAdvice.toLowerCase().contains(q) ||
        precautions.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }
}

class SeasonCalendarItem {
  const SeasonCalendarItem({required this.month, required this.fruits});

  factory SeasonCalendarItem.fromJson(Map<String, dynamic> json) =>
      SeasonCalendarItem(
        month: json['month'] as String? ?? '',
        fruits: (json['fruits'] as List<dynamic>? ?? []).cast<String>(),
      );

  final String month;
  final List<String> fruits;
}

class KnowledgeTopic {
  const KnowledgeTopic({
    required this.id,
    required this.category,
    required this.title,
    this.alertLevel = 'none',
    this.bullets = const [],
    this.tables = const [],
    this.subsections = const [],
  });

  factory KnowledgeTopic.fromJson(Map<String, dynamic> json) => KnowledgeTopic(
        id: json['id'] as String? ?? '',
        category: json['category'] as String? ?? '',
        title: json['title'] as String? ?? '',
        alertLevel: json['alertLevel'] as String? ?? 'none',
        bullets: (json['bullets'] as List<dynamic>? ?? []).cast<String>(),
        tables: (json['tables'] as List<dynamic>? ?? [])
            .map((t) => (t as List<dynamic>)
                .map((row) =>
                    (row as Map<String, dynamic>).cast<String, String>())
                .toList())
            .toList(),
        subsections: (json['subsections'] as List<dynamic>? ?? [])
            .map((e) =>
                KnowledgeSubsection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String category;
  final String title;
  final String alertLevel;
  final List<String> bullets;
  final List<List<Map<String, String>>> tables;
  final List<KnowledgeSubsection> subsections;

  bool matches(String q) {
    if (category.toLowerCase().contains(q) ||
        title.toLowerCase().contains(q)) {
      return true;
    }
    for (final b in bullets) {
      if (b.toLowerCase().contains(q)) return true;
    }
    for (final tbl in tables) {
      for (final row in tbl) {
        for (final v in row.values) {
          if (v.toLowerCase().contains(q)) return true;
        }
      }
    }
    for (final s in subsections) {
      if (s.matches(q)) return true;
    }
    return false;
  }
}

class KnowledgeSubsection {
  const KnowledgeSubsection({
    required this.title,
    this.bullets = const [],
    this.tables = const [],
  });

  factory KnowledgeSubsection.fromJson(Map<String, dynamic> json) =>
      KnowledgeSubsection(
        title: json['title'] as String? ?? '',
        bullets: (json['bullets'] as List<dynamic>? ?? []).cast<String>(),
        tables: (json['tables'] as List<dynamic>? ?? [])
            .map((t) => (t as List<dynamic>)
                .map((row) => (row as Map<String, dynamic>).cast<String, String>())
                .toList())
            .toList(),
      );

  final String title;
  final List<String> bullets;
  final List<List<Map<String, String>>> tables;

  bool matches(String q) {
    if (title.toLowerCase().contains(q)) return true;
    for (final b in bullets) {
      if (b.toLowerCase().contains(q)) return true;
    }
    for (final tbl in tables) {
      for (final row in tbl) {
        for (final v in row.values) {
          if (v.toLowerCase().contains(q)) return true;
        }
      }
    }
    return false;
  }
}

class DrugInteractionItem {
  const DrugInteractionItem({
    required this.drugCategory,
    required this.avoidFood,
    required this.mechanism,
    required this.source,
    required this.alertLevel,
  });

  factory DrugInteractionItem.fromJson(Map<String, dynamic> json) =>
      DrugInteractionItem(
        drugCategory: json['drugCategory'] as String? ?? '',
        avoidFood: json['avoidFood'] as String? ?? '',
        mechanism: json['mechanism'] as String? ?? '',
        source: json['source'] as String? ?? '',
        alertLevel: json['alertLevel'] as String? ?? 'warning',
      );

  final String drugCategory;
  final String avoidFood;
  final String mechanism;
  final String source;
  final String alertLevel;

  bool matches(String q) =>
      drugCategory.toLowerCase().contains(q) ||
      avoidFood.toLowerCase().contains(q) ||
      mechanism.toLowerCase().contains(q) ||
      source.toLowerCase().contains(q);
}

class RumorItem {
  const RumorItem({
    required this.id,
    required this.claim,
    required this.truth,
    required this.source,
  });

  factory RumorItem.fromJson(Map<String, dynamic> json) => RumorItem(
        id: json['id'] as String? ?? '',
        claim: json['claim'] as String? ?? '',
        truth: json['truth'] as String? ?? '',
        source: json['source'] as String? ?? '',
      );

  final String id;
  final String claim;
  final String truth;
  final String source;

  bool matches(String q) =>
      claim.toLowerCase().contains(q) ||
      truth.toLowerCase().contains(q) ||
      source.toLowerCase().contains(q);
}

class ReplacementScheduleItem {
  const ReplacementScheduleItem({required this.item, required this.cycle});

  factory ReplacementScheduleItem.fromJson(Map<String, dynamic> json) =>
      ReplacementScheduleItem(
        item: json['item'] as String? ?? '',
        cycle: json['cycle'] as String? ?? '',
      );

  final String item;
  final String cycle;
}

class CheckupScheduleItem {
  const CheckupScheduleItem({
    required this.item,
    required this.frequency,
    required this.target,
    required this.notes,
  });

  factory CheckupScheduleItem.fromJson(Map<String, dynamic> json) =>
      CheckupScheduleItem(
        item: json['item'] as String? ?? '',
        frequency: json['frequency'] as String? ?? '',
        target: json['target'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );

  final String item;
  final String frequency;
  final String target;
  final String notes;

  bool matches(String q) =>
      item.toLowerCase().contains(q) ||
      frequency.toLowerCase().contains(q) ||
      target.toLowerCase().contains(q) ||
      notes.toLowerCase().contains(q);
}

class LifecycleSearchResult {
  const LifecycleSearchResult({
    required this.id,
    required this.sourceBadge,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.details,
    this.alertLevel = 'none',
    this.warningText,
    this.tags = const [],
  });

  final String id;
  final String sourceBadge;
  final String title;
  final String subtitle;
  final String summary;
  final String details;
  final String alertLevel;
  final String? warningText;
  final List<String> tags;
}
