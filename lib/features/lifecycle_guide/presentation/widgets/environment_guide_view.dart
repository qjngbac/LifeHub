import 'package:flutter/material.dart';
import 'package:lifehub/features/lifecycle_guide/domain/lifecycle_models.dart';
import 'package:lifehub/features/lifecycle_guide/presentation/widgets/lifecycle_detail_sheet.dart';

class EnvironmentGuideView extends StatefulWidget {
  const EnvironmentGuideView({
    super.key,
    required this.topics,
    required this.replacementSchedule,
  });

  final List<KnowledgeTopic> topics;
  final List<ReplacementScheduleItem> replacementSchedule;

  @override
  State<EnvironmentGuideView> createState() => _EnvironmentGuideViewState();
}

class _EnvironmentGuideViewState extends State<EnvironmentGuideView> {
  String _selectedCategory = '全部';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final categories = const [
      '全部',
      '居家环境',
      '日化清洁安全',
      '衣物鞋袜',
      '物品更换周期',
    ];

    return Column(
      children: [
        // Category Chips (Fixed at top)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 40,
            child: ListView.separated(
              key: const PageStorageKey('env_guide_categories'),
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
            key: PageStorageKey('env_guide_list_$_selectedCategory'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [

        // Replacement Schedule Section
        if (_selectedCategory == '全部' ||
            _selectedCategory == '物品更换周期') ...[
          const _SectionHeader(
            title: '全品类日常用品更换周期总表',
            subtitle: '超期不换易滋生真菌、物理衰减、失去保护或二次污染',
          ),
          const SizedBox(height: 10),
          Card(
            color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: colorScheme.tertiary.withValues(alpha: 0.3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history_toggle_off,
                          color: colorScheme.tertiary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '定期更换关键清单',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final item in widget.replacementSchedule)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.item,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.cycle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

              for (final topic in widget.topics) ...[
                if (_selectedCategory == '全部' ||
                    _selectedCategory == topic.category) ...[
                  _EnvTopicCard(
                    key: ValueKey('env_topic_${topic.id}'),
                    topic: topic,
                  ),
                  const SizedBox(height: 10),
                ],
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

class _EnvTopicCard extends StatefulWidget {
  const _EnvTopicCard({super.key, required this.topic});

  final KnowledgeTopic topic;

  @override
  State<_EnvTopicCard> createState() => _EnvTopicCardState();
}

class _EnvTopicCardState extends State<_EnvTopicCard> {
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
      sourceBadge: '日用环境 · ${widget.topic.category}',
      details: lines.join('\n\n'),
      alertLevel: widget.topic.alertLevel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topic = widget.topic;
    final isDanger = topic.alertLevel == 'danger';
    final isWarning = topic.alertLevel == 'warning';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDanger
              ? colorScheme.error.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                  Icon(
                    isDanger
                        ? Icons.error_outline
                        : isWarning
                            ? Icons.warning_amber_rounded
                            : Icons.spa_outlined,
                    color: isDanger
                        ? colorScheme.error
                        : isWarning
                            ? colorScheme.tertiary
                            : colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          topic.category,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
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
                                    const EdgeInsets.symmetric(vertical: 2),
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
                                        style: theme.textTheme.bodySmall,
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

