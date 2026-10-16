import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/goal/presentation/goal_detail_page.dart';
import 'package:lifehub/features/project/presentation/projects_page.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/search/data/search_repository.dart';
import 'package:lifehub/features/search/presentation/entity_detail_page.dart';

class EntityRelationsPanel extends ConsumerStatefulWidget {
  const EntityRelationsPanel({
    super.key,
    required this.entity,
    this.compact = false,
  });

  final EntityReference entity;
  final bool compact;

  @override
  ConsumerState<EntityRelationsPanel> createState() =>
      _EntityRelationsPanelState();
}

class _EntityRelationsPanelState extends ConsumerState<EntityRelationsPanel> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = RelationRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);
    return FutureBuilder<List<EntityRelation>>(
      key: ValueKey(revision),
      future: repository.relationsFor(widget.entity),
      builder: (context, snapshot) {
        final relations = snapshot.data ?? const <EntityRelation>[];
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
            padding: const EdgeInsets.all(14),
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
                      child: Icon(
                        Icons.hub_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '双向关联网络',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            relations.isEmpty
                                ? '未建立关联'
                                : '已连接 ${relations.length} 个相关实体',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _add(repository),
                      icon: const Icon(Icons.add_link, size: 16),
                      label: const Text('添加关联'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: LinearProgressIndicator()),
                  )
                else if (relations.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.link_off_outlined,
                          size: 32,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '暂无双向关联',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '点击右上角“添加关联”，可与任务、目标、日程、地点或资料建立网状连接',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...relations.map(
                    (relation) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: ListTile(
                        dense: widget.compact,
                        contentPadding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: typeColor(relation.entity.reference.type).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            entityIcon(relation.entity.reference.type),
                            size: 18,
                            color: typeColor(relation.entity.reference.type),
                          ),
                        ),
                        title: Text(
                          relation.entity.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: typeColor(relation.entity.reference.type).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  typeName(relation.entity.reference.type),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: typeColor(relation.entity.reference.type),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  relationTypeName(relation.relationType),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (relation.note != null && relation.note!.trim().isNotEmpty)
                                Text(
                                  relation.note!.trim(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '解除关联',
                              icon: const Icon(Icons.link_off, size: 20),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('解除关联'),
                                    content: Text('确定要解除与“${relation.entity.title}”的双向关联吗？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('解除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await repository.unlink(
                                    widget.entity,
                                    relation.entity.reference,
                                  );
                                  if (mounted) setState(() => revision++);
                                }
                              },
                            ),
                            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                          ],
                        ),
                        onTap: () => _navigateToDetail(context, relation.entity),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToDetail(
    BuildContext context,
    RelatedEntity entity,
  ) async {
    final type = entity.reference.type.toUpperCase();
    final id = entity.reference.id;
    if (type == 'GOAL') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GoalDetailPage(goalId: id)),
      );
      return;
    }
    if (type == 'PROJECT') {
      final database = ref.read(databaseProvider);
      final project = await (database.select(database.projects)
            ..where((p) => p.id.equals(id)))
          .getSingleOrNull();
      if (project != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ProjectDetailPage(project: project)),
        );
        return;
      }
    }
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EntityDetailPage(
            result: SearchResult(
              type: entity.reference.type,
              id: entity.reference.id,
              title: entity.title,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _add(RelationRepository repository) async {
    final allCandidates = (await repository.candidates())
        .where((value) => value.reference.key != widget.entity.key)
        .toList();
    if (!mounted) return;

    final result = await showModalBottomSheet<
        ({RelatedEntity entity, String relationType, String? note})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddRelationSheet(
        allCandidates: allCandidates,
        currentEntity: widget.entity,
      ),
    );

    if (result != null) {
      await repository.link(
        widget.entity,
        result.entity.reference,
        relationType: result.relationType,
        note: result.note,
      );
      if (mounted) setState(() => revision++);
    }
  }
}

/// 底部防溢出自适应关联面板
class _AddRelationSheet extends StatefulWidget {
  const _AddRelationSheet({
    required this.allCandidates,
    required this.currentEntity,
  });

  final List<RelatedEntity> allCandidates;
  final EntityReference currentEntity;

  @override
  State<_AddRelationSheet> createState() => _AddRelationSheetState();
}

class _AddRelationSheetState extends State<_AddRelationSheet> {
  String filterQuery = '';
  String selectedType = 'ALL';
  RelatedEntity? pickedEntity;
  String relationType = 'RELATED';
  final noteController = TextEditingController();

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.78;

    final filtered = widget.allCandidates.where((c) {
      if (selectedType != 'ALL' && c.reference.type.toUpperCase() != selectedType) {
        return false;
      }
      if (filterQuery.isNotEmpty &&
          !c.title.toLowerCase().contains(filterQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    pickedEntity == null ? '选择要关联的内容' : '配置关联关系',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (pickedEntity != null)
                    TextButton(
                      onPressed: () => setState(() => pickedEntity = null),
                      child: const Text('重选实体'),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (pickedEntity == null) ...[
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: '搜索标题...',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) => setState(() => filterQuery = val),
                ),
                const SizedBox(height: 8),
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
                        ('账目', 'FINANCE'),
                        ('阅读', 'READING'),
                        ('维护', 'MAINTENANCE'),
                        ('订阅', 'SUBSCRIPTION'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            showCheckmark: false,
                            label: Text(label, style: const TextStyle(fontSize: 12)),
                            selected: selectedType == val,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => selectedType = val),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('没有找到可关联的内容'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final color = typeColor(item.reference.type);
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  entityIcon(item.reference.type),
                                  size: 16,
                                  color: color,
                                ),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                typeName(item.reference.type),
                                style: TextStyle(fontSize: 11, color: color),
                              ),
                              trailing: const Icon(Icons.chevron_right, size: 18),
                              onTap: () => setState(() => pickedEntity = item),
                            );
                          },
                        ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entityIcon(pickedEntity!.reference.type),
                        color: typeColor(pickedEntity!.reference.type),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedEntity!.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        typeName(pickedEntity!.reference.type),
                        style: TextStyle(
                          fontSize: 11,
                          color: typeColor(pickedEntity!.reference.type),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '关联关系类型',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final (label, val) in [
                      ('相关', 'RELATED'),
                      ('依赖于', 'DEPENDS_ON'),
                      ('属于', 'BELONGS_TO'),
                      ('包含', 'PARENT_OF'),
                      ('参考依据', 'REFERENCE'),
                    ])
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(label),
                        selected: relationType == val,
                        onSelected: (_) => setState(() => relationType = val),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: '关联备注说明（可选）',
                    hintText: '如：核心前置依据、参考资料等',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        (
                          entity: pickedEntity!,
                          relationType: relationType,
                          note: noteController.text.trim().isEmpty
                              ? null
                              : noteController.text.trim(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('确认建立关联'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color typeColor(String type) => switch (type.toUpperCase()) {
      'TASK' => const Color(0xFF1976D2),
      'GOAL' => const Color(0xFFE65100),
      'PROJECT' => const Color(0xFF6A1B9A),
      'EVENT' => const Color(0xFF00897B),
      'COURSE' => const Color(0xFF0288D1),
      'LOCATION' => const Color(0xFFC2185B),
      'SAVED_ITEM' => const Color(0xFF5D4037),
      'TRIP' => const Color(0xFF0097A7),
      'HOUSEHOLD' => const Color(0xFF455A64),
      'FINANCE' => const Color(0xFF2E7D32),
      'CREDENTIAL' => const Color(0xFF512DA8),
      'SUBSCRIPTION' => const Color(0xFFF57C00),
      'MAINTENANCE' => const Color(0xFF7B1FA2),
      'READING' => const Color(0xFF388E3C),
      'PARCEL' => const Color(0xFFD84315),
      _ => const Color(0xFF546E7A),
    };

IconData entityIcon(String type) => switch (type.toUpperCase()) {
      'TASK' => Icons.check_circle_outline,
      'GOAL' => Icons.flag_outlined,
      'PROJECT' => Icons.folder_outlined,
      'TRIP' => Icons.luggage_outlined,
      'LOCATION' => Icons.place_outlined,
      'SAVED_ITEM' => Icons.bookmark_outline,
      'HOUSEHOLD' => Icons.inventory_2_outlined,
      'FINANCE' => Icons.receipt_long_outlined,
      'CREDENTIAL' => Icons.badge_outlined,
      'EVENT' => Icons.event_outlined,
      'COURSE' => Icons.school_outlined,
      'SUBSCRIPTION' => Icons.autorenew,
      'MAINTENANCE' => Icons.home_repair_service_outlined,
      'READING' => Icons.menu_book_outlined,
      'PARCEL' => Icons.local_shipping_outlined,
      _ => Icons.link,
    };

String typeName(String type) => switch (type.toUpperCase()) {
      'TASK' => '任务',
      'GOAL' => '目标',
      'PROJECT' => '项目',
      'TRIP' => '旅行',
      'LOCATION' => '地点',
      'SAVED_ITEM' => '资料',
      'HOUSEHOLD' => '家庭物品',
      'FINANCE' => '收支记录',
      'CREDENTIAL' => '证件',
      'EVENT' => '日程',
      'COURSE' => '课程',
      'SUBSCRIPTION' => '订阅',
      'MAINTENANCE' => '维护计划',
      'READING' => '阅读进度',
      'PARCEL' => '快递',
      _ => type,
    };

String relationTypeName(String type) => switch (type.toUpperCase()) {
      'DEPENDS_ON' => '依赖于',
      'BELONGS_TO' => '属于',
      'PARENT_OF' => '包含',
      'REFERENCE' => '参考依据',
      'BLOCKED_BY' => '阻塞于',
      'RELATED' => '相关',
      _ => type,
    };
