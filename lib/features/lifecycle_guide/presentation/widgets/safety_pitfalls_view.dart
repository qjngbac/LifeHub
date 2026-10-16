import 'package:flutter/material.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_detail_sheet.dart';

class SafetyPitfallsView extends StatefulWidget {
  const SafetyPitfallsView({
    super.key,
    required this.drugInteractions,
    required this.rumors,
    required this.checkups,
    required this.exerciseTopics,
    required this.commonPitfalls,
  });

  final List<DrugInteractionItem> drugInteractions;
  final List<RumorItem> rumors;
  final List<CheckupScheduleItem> checkups;
  final List<KnowledgeTopic> exerciseTopics;
  final List<String> commonPitfalls;

  @override
  State<SafetyPitfallsView> createState() => _SafetyPitfallsViewState();
}

class _SafetyPitfallsViewState extends State<SafetyPitfallsView> {
  String _selectedCategory = '全部';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final categories = [
      '全部',
      '🚨 药物相互作用 (${widget.drugInteractions.length})',
      '🛡️ 科学辟谣清单 (${widget.rumors.length})',
      '📋 体检筛查表 (${widget.checkups.length})',
      '🏃 运动处方 (${widget.exerciseTopics.length})',
      '⚠️ 通用误区 (${widget.commonPitfalls.length})',
    ];

    return Column(
      children: [
        // Category chips (Fixed at top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              key: const PageStorageKey('safety_pitfalls_categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = categories[i];
                return FilterChip(
                  label: Text(cat),
                  selected: _selectedCategory == cat,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = cat);
                  },
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: PageStorageKey('safety_pitfalls_list_$_selectedCategory'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [

        // Drug Interactions Section
        if (_selectedCategory == '全部' ||
            _selectedCategory.startsWith('🚨 药物相互作用')) ...[
          const _SectionHeader(
            title: '药物 · 食物 · 补充剂相互作用总表',
            subtitle: '西柚他汀、高钾降压药、华法林维K、酪胺MAOI、鞣酸铁钙等致命/减效禁忌',
          ),
          const SizedBox(height: 10),
          for (final item in widget.drugInteractions) ...[
            _DrugInteractionCard(item: item),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],

        // Rumor Busters Section
        if (_selectedCategory == '全部' ||
            _selectedCategory.startsWith('🛡️ 科学辟谣清单')) ...[
          const _SectionHeader(
            title: '常见生活谣言与科学事实纠偏总清单',
            subtitle: '基于循证医学与毒理学标准的辟谣真相',
          ),
          const SizedBox(height: 10),
          for (final rumor in widget.rumors) ...[
            _RumorCard(rumor: rumor),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],

        // Checkup Schedule Section
        if (_selectedCategory == '全部' ||
            _selectedCategory.startsWith('📋 体检筛查表')) ...[
          const _SectionHeader(
            title: '全生命周期健康筛查与体检时间表',
            subtitle: '各年龄阶段必查项与个性化筛查建议',
          ),
          const SizedBox(height: 10),
          for (final checkup in widget.checkups) ...[
            _CheckupCard(checkup: checkup),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],

        // Exercise Prescriptions Section
        if (_selectedCategory == '全部' ||
            _selectedCategory.startsWith('🏃 运动处方')) ...[
          const _SectionHeader(
            title: '全生命周期运动处方指南',
            subtitle: '回报率最高、成本最低的健康干预方案',
          ),
          const SizedBox(height: 10),
          for (final ex in widget.exerciseTopics) ...[
            _ExerciseCard(
              key: ValueKey('exercise_${ex.id}'),
              topic: ex,
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],

        // Common Pitfalls Section
        if (_selectedCategory == '全部' ||
            _selectedCategory.startsWith('⚠️ 通用误区')) ...[
          const _SectionHeader(
            title: '选品通用避坑误区',
            subtitle: '避免刺激叠加、反跳伤害或营销智商税',
          ),
          const SizedBox(height: 10),
          Card(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.commonPitfalls.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.commonPitfalls[i],
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  ),
],
);
}
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _DrugInteractionCard extends StatelessWidget {
  const _DrugInteractionCard({required this.item});

  final DrugInteractionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDanger = item.alertLevel == 'danger';

    return Card(
      elevation: 0,
      color: isDanger
          ? colorScheme.errorContainer.withValues(alpha: 0.4)
          : colorScheme.tertiaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDanger
              ? colorScheme.error.withValues(alpha: 0.4)
              : colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showLifecycleDetailSheet(
            context,
            title: '${item.drugCategory} ✕ ${item.avoidFood}',
            sourceBadge: '药物禁忌 · ${item.source}',
            details: '【药物类别】${item.drugCategory}\n\n'
                '【需避开的食物/补充剂】${item.avoidFood}\n\n'
                '【机制与严重后果】${item.mechanism}',
            alertLevel: item.alertLevel,
            warningText: item.mechanism,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isDanger ? Icons.error_outline : Icons.warning_amber_rounded,
                    size: 18,
                    color: isDanger ? colorScheme.error : colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.drugCategory,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDanger
                            ? colorScheme.onErrorContainer
                            : colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  Text(
                    item.source,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '避开食物：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.avoidFood,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDanger ? colorScheme.error : colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.mechanism,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RumorCard extends StatelessWidget {
  const _RumorCard({required this.rumor});

  final RumorItem rumor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showLifecycleDetailSheet(
            context,
            title: rumor.claim,
            sourceBadge: '辟谣清单 · 科学真相',
            details: '【流传说法】${rumor.claim}\n\n'
                '【科学真相】${rumor.truth}\n\n'
                '【出处与规范】${rumor.source}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('❌ ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      rumor.claim,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✅ ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      rumor.truth,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckupCard extends StatelessWidget {
  const _CheckupCard({required this.checkup});

  final CheckupScheduleItem checkup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showLifecycleDetailSheet(
            context,
            title: checkup.item,
            sourceBadge: '全生命周期 · 体检筛查',
            details: '【检查项目】${checkup.item}\n\n'
                '【建议频次/周期】${checkup.frequency}\n\n'
                '【适用人群】${checkup.target}\n\n'
                '【筛查要点与注意事项】${checkup.notes}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      checkup.item,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.event_repeat_rounded,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        checkup.frequency,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '人群：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      checkup.target,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (checkup.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '要点：',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        checkup.notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({super.key, required this.topic});

  final KnowledgeTopic topic;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  bool _isExpanded = false;

  void _openDetailSheet() {
    final lines = <String>[];
    for (final b in widget.topic.bullets) {
      lines.add('• $b');
    }
    for (final tbl in widget.topic.tables) {
      for (final r in tbl) {
        lines.add(r.entries.map((e) => '${e.key}：${e.value}').join(' | '));
      }
    }
    showLifecycleDetailSheet(
      context,
      title: widget.topic.title,
      sourceBadge: '科学运动处方',
      details: lines.join('\n\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topic = widget.topic;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.fitness_center_outlined,
                      color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topic.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '查看与复制详情',
                    icon: const Icon(Icons.open_in_new, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _openDetailSheet,
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                ],
              ),
              if (!_isExpanded && topic.bullets.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  topic.bullets.first,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (_isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                for (final b in topic.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            )),
                        Expanded(
                          child: Text(
                            b,
                            style:
                                theme.textTheme.bodySmall?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (topic.tables.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final tbl in topic.tables) ...[
                    for (final row in tbl)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in row.entries)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2.5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 76,
                                      child: Text(
                                        e.key,
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.outline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

