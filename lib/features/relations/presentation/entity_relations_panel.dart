import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/relations/data/relation_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';

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
    return FutureBuilder<List<EntityRelation>>(
      key: ValueKey(revision),
      future: repository.relationsFor(widget.entity),
      builder: (context, snapshot) {
        final relations = snapshot.data ?? const <EntityRelation>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.hub_outlined),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('关联关系')),
                  TextButton.icon(
                    onPressed: () => _add(repository),
                    icon: const Icon(Icons.add),
                    label: const Text('关联'),
                  ),
                ]),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator()
                else if (relations.isEmpty)
                  const Text('暂时没有关联，可连接任务、目标、项目、旅行、地点或资料。')
                else
                  ...relations.map((relation) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: widget.compact,
                        leading: Icon(_icon(relation.entity.reference.type)),
                        title: Text(relation.entity.title),
                        subtitle: Text([
                          _typeName(relation.entity.reference.type),
                          relation.relationType,
                          if (relation.note != null) relation.note!,
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: '取消关联',
                          icon: const Icon(Icons.link_off),
                          onPressed: () async {
                            await repository.unlink(
                              widget.entity,
                              relation.entity.reference,
                            );
                            if (mounted) setState(() => revision++);
                          },
                        ),
                      )),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _add(RelationRepository repository) async {
    final candidates = (await repository.candidates())
        .where((value) => value.reference.key != widget.entity.key)
        .toList();
    if (!mounted) return;
    final selected = await showDialog<RelatedEntity>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('选择要关联的内容'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: candidates.isEmpty
              ? const Center(child: Text('暂无可关联内容'))
              : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final value = candidates[index];
                    return ListTile(
                      leading: Icon(_icon(value.reference.type)),
                      title: Text(value.title),
                      subtitle: Text(_typeName(value.reference.type)),
                      onTap: () => Navigator.pop(context, value),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await repository.link(widget.entity, selected.reference);
    if (mounted) setState(() => revision++);
  }
}

IconData _icon(String type) => switch (type.toUpperCase()) {
      'TASK' => Icons.check_circle_outline,
      'GOAL' => Icons.flag_outlined,
      'PROJECT' => Icons.folder_outlined,
      'TRIP' => Icons.luggage_outlined,
      'LOCATION' => Icons.place_outlined,
      'SAVED_ITEM' => Icons.bookmark_outline,
      'HOUSEHOLD' => Icons.inventory_2_outlined,
      'FINANCE' => Icons.receipt_long_outlined,
      'EVENT' => Icons.event_outlined,
      'COURSE' => Icons.school_outlined,
      'SUBSCRIPTION' => Icons.autorenew,
      'MAINTENANCE' => Icons.home_repair_service_outlined,
      'READING' => Icons.menu_book_outlined,
      'PARCEL' => Icons.local_shipping_outlined,
      _ => Icons.link,
    };

String _typeName(String type) => switch (type.toUpperCase()) {
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
