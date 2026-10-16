import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class RelationCenterPage extends ConsumerStatefulWidget {
  const RelationCenterPage({super.key, this.initialEntity});
  final EntityReference? initialEntity;

  @override
  ConsumerState<RelationCenterPage> createState() => _RelationCenterPageState();
}

class _RelationCenterPageState extends ConsumerState<RelationCenterPage> {
  EntityReference? selected;
  String query = '';
  String filterType = 'ALL';

  @override
  void initState() {
    super.initState();
    selected = widget.initialEntity;
  }

  @override
  Widget build(BuildContext context) {
    final repository = RelationRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);
    final isSearching = query.trim().isNotEmpty || filterType != 'ALL';

    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selected != null) {
          setState(() => selected = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selected != null ? '实体关联网络' : '统一关联中心'),
          leading: selected != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回关联总览',
                  onPressed: () => setState(() => selected = null),
                )
              : null,
          actions: [
            if (selected != null)
              TextButton.icon(
                onPressed: () => setState(() => selected = null),
                icon: const Icon(Icons.clear_all),
                label: const Text('返回总览'),
              ),
          ],
        ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (selected != null) ...[
            _FocusedEntityHeader(
              reference: selected!,
              repository: repository,
              onClear: () => setState(() => selected = null),
            ),
            const SizedBox(height: 12),
            EntityRelationsPanel(
              key: ValueKey(selected!.key),
              entity: selected!,
            ),
          ] else ...[
            SearchBar(
              hintText: '搜索任务、目标、项目、地点、资料等',
              leading: const Icon(Icons.search),
              trailing: query.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => query = ''),
                      ),
                    ]
                  : null,
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (label, val) in [
                    ('全部', 'ALL'),
                    ('任务', 'TASK'),
                    ('目标', 'GOAL'),
                    ('项目', 'PROJECT'),
                    ('日程', 'EVENT'),
                    ('课程', 'COURSE'),
                    ('地点', 'LOCATION'),
                    ('资料', 'SAVED_ITEM'),
                    ('快递', 'PARCEL'),
                    ('物资', 'HOUSEHOLD'),
                    ('收支', 'FINANCE'),
                    ('阅读', 'READING'),
                    ('维护', 'MAINTENANCE'),
                    ('订阅', 'SUBSCRIPTION'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: filterType == val,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => filterType = val),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (isSearching)
              FutureBuilder<List<RelatedEntity>>(
                future: repository.candidates(query: query, type: filterType),
                builder: (context, snapshot) {
                  final candidates = snapshot.data ?? const <RelatedEntity>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (candidates.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 40, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            '未找到匹配的实体',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          '匹配实体 (${candidates.length})，点击聚焦关联：',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      ...candidates.map((entity) {
                        final color = typeColor(entity.reference.type);
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            leading: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                entityIcon(entity.reference.type),
                                size: 18,
                                color: color,
                              ),
                            ),
                            title: Text(
                              entity.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              typeName(entity.reference.type),
                              style: TextStyle(fontSize: 11, color: color),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                            onTap: () => setState(() => selected = entity.reference),
                          ),
                        );
                      }),
                    ],
                  );
                },
              )
            else ...[
              _GlobalOverviewCard(
                repository: repository,
                onSelectHub: (ref) => setState(() => selected = ref),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.explore_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '探索近期实体',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<RelatedEntity>>(
                future: repository.candidates(),
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const <RelatedEntity>[];
                  if (list.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      for (final entity in list.take(6))
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: typeColor(entity.reference.type).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                entityIcon(entity.reference.type),
                                size: 16,
                                color: typeColor(entity.reference.type),
                              ),
                            ),
                            title: Text(
                              entity.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                            subtitle: Text(
                              typeName(entity.reference.type),
                              style: TextStyle(
                                fontSize: 10,
                                color: typeColor(entity.reference.type),
                              ),
                            ),
                            trailing: const Icon(Icons.hub_outlined, size: 16, color: Colors.grey),
                            onTap: () => setState(() => selected = entity.reference),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ],
      ),
    ),
  );
}
}

/// 聚焦实体的优雅头部卡片（解析真实标题，绝不展示机器码）
class _FocusedEntityHeader extends StatelessWidget {
  const _FocusedEntityHeader({
    required this.reference,
    required this.repository,
    required this.onClear,
  });

  final EntityReference reference;
  final RelationRepository repository;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = typeColor(reference.type);
    final typeStr = typeName(reference.type);

    return FutureBuilder<RelatedEntity?>(
      future: repository.resolveEntity(reference),
      builder: (context, snapshot) {
        final title = snapshot.data?.title ?? reference.type;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: color.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          color: color.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(entityIcon(reference.type), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              typeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '当前聚焦实体',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '返回总览',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlobalOverviewCard extends StatelessWidget {
  const _GlobalOverviewCard({
    required this.repository,
    required this.onSelectHub,
  });

  final RelationRepository repository;
  final ValueChanged<EntityReference> onSelectHub;

  @override
  Widget build(BuildContext context) => FutureBuilder<RelationOverviewStats>(
        future: repository.getOverviewStats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final stats = snapshot.data!;
          final theme = Theme.of(context);

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.hub_outlined,
                            size: 18, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '全局网状网络概览',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stats.totalLinks}',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '关联链接总数',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stats.linkedEntitiesCount}',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '已连接实体数',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (stats.topHubs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '暂无网络关联。先点击下方实体，即可建立双向关联。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'TOP 核心生活枢纽',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final hub in stats.topHubs)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: typeColor(hub.entity.reference.type)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            entityIcon(hub.entity.reference.type),
                            size: 16,
                            color: typeColor(hub.entity.reference.type),
                          ),
                        ),
                        title: Text(
                          hub.entity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${typeName(hub.entity.reference.type)} · ${hub.count} 个双向关联',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios,
                            size: 14, color: Colors.grey),
                        onTap: () => onSelectHub(hub.entity.reference),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}
