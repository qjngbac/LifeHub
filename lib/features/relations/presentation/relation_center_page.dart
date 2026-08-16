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

  @override
  void initState() {
    super.initState();
    selected = widget.initialEntity;
  }

  @override
  Widget build(BuildContext context) {
    final repository = RelationRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('统一关联中心')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: '查找任务、目标、项目、地点或资料',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<RelatedEntity>>(
            future: repository.candidates(query: query),
            builder: (context, snapshot) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entity in snapshot.data ?? const <RelatedEntity>[])
                  ChoiceChip(
                    label: Text(entity.title),
                    selected: selected?.key == entity.reference.key,
                    onSelected: (_) =>
                        setState(() => selected = entity.reference),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (selected == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('先选择一条内容，即可查看并维护它的双向关联。'),
              ),
            )
          else
            EntityRelationsPanel(
              key: ValueKey(selected!.key),
              entity: selected!,
            ),
        ],
      ),
    );
  }
}
