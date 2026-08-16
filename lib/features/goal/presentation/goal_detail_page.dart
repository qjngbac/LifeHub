import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.goalId});
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = GoalRepository(ref.read(databaseProvider));
    return FutureBuilder(
      future: Future.wait([
        repository.get(goalId),
        repository.milestones(goalId),
        repository.progress(goalId),
        repository.links(goalId),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final goal = snapshot.data![0] as GoalEntry;
        final milestones = snapshot.data![1] as List<MilestoneEntry>;
        final progress = snapshot.data![2] as double;
        final links = snapshot.data![3] as List<EntityLinkEntry>;
        return Scaffold(
          appBar: AppBar(title: Text(goal.name)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => switch (goal.progressMode) {
              GoalProgressMode.manual =>
                _setManualProgress(context, ref, repository, goal),
              GoalProgressMode.task =>
                _addLink(context, ref, repository, goal, 'TASK'),
              GoalProgressMode.project =>
                _addLink(context, ref, repository, goal, 'PROJECT'),
              _ => _addMilestone(context, ref, repository),
            },
            icon: Icon(goal.progressMode == GoalProgressMode.manual
                ? Icons.tune
                : Icons.add),
            label: Text(switch (goal.progressMode) {
              GoalProgressMode.manual => '调整进度',
              GoalProgressMode.task => '关联任务',
              GoalProgressMode.project => '关联项目',
              _ => '里程碑',
            }),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('总体进度',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).round()}%'),
                      if (goal.description != null) ...[
                        const SizedBox(height: 12),
                        Text(goal.description!),
                      ],
                    ],
                  ),
                ),
              ),
              EntityRelationsPanel(
                entity: EntityReference(type: 'GOAL', id: goal.id),
              ),
              if (goal.progressMode == GoalProgressMode.milestone) ...[
                Text('里程碑', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (milestones.isEmpty)
                  const Card(child: ListTile(title: Text('还没有里程碑')))
                else
                  ...milestones.map((milestone) => Card(
                        child: CheckboxListTile(
                          value: milestone.completedAt != null,
                          title: Text(milestone.name),
                          onChanged: (value) async {
                            await repository.completeMilestone(
                              milestone.id,
                              completed: value == true,
                            );
                            ref.read(refreshProvider.notifier).state++;
                          },
                        ),
                      )),
              ] else if (goal.progressMode == GoalProgressMode.manual) ...[
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.touch_app_outlined),
                    title: Text('手工进度'),
                    subtitle: Text('进度由你直接调整，不需要创建里程碑。'),
                  ),
                ),
              ] else ...[
                Text(
                  goal.progressMode == GoalProgressMode.task ? '关联任务' : '关联项目',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (links.isEmpty)
                  const Card(child: ListTile(title: Text('还没有关联对象')))
                else
                  ...links.map((link) => Card(
                        child: ListTile(
                          leading: Icon(link.targetType == 'TASK'
                              ? Icons.task_alt_outlined
                              : Icons.folder_outlined),
                          title: FutureBuilder<String>(
                            future: _linkTitle(ref, link),
                            builder: (context, value) =>
                                Text(value.data ?? '加载中…'),
                          ),
                          trailing: IconButton(
                            tooltip: '取消关联',
                            icon: const Icon(Icons.link_off),
                            onPressed: () async {
                              await repository.unlink(
                                goal.id,
                                link.targetType,
                                link.targetId,
                              );
                              ref.read(refreshProvider.notifier).state++;
                            },
                          ),
                        ),
                      )),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _setManualProgress(
    BuildContext context,
    WidgetRef ref,
    GoalRepository repository,
    GoalEntry goal,
  ) async {
    var value = goal.manualProgress ?? 0;
    final changed = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('调整手工进度'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(value * 100).round()}%'),
            Slider(
              value: value,
              divisions: 100,
              onChanged: (next) => setLocal(() => value = next),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (changed == null) return;
    await repository.updateManualProgress(goal.id, changed);
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _addLink(
    BuildContext context,
    WidgetRef ref,
    GoalRepository repository,
    GoalEntry goal,
    String targetType,
  ) async {
    final database = ref.read(databaseProvider);
    final existing = (await repository.links(goal.id))
        .where((link) => link.targetType == targetType)
        .map((link) => link.targetId)
        .toSet();
    final candidates = targetType == 'TASK'
        ? (await (database.select(database.tasks)
                  ..where((row) => row.deletedAt.isNull()))
                .get())
            .where((row) => !existing.contains(row.id))
            .map((row) => (row.id, row.title))
            .toList()
        : (await (database.select(database.projects)
                  ..where((row) => row.deletedAt.isNull()))
                .get())
            .where((row) => !existing.contains(row.id))
            .map((row) => (row.id, row.name))
            .toList();
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: candidates.isEmpty
            ? const ListTile(title: Text('没有可关联的对象'))
            : ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text(targetType == 'TASK' ? '选择任务' : '选择项目'),
                    trailing: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      title: Text(candidate.$2),
                      onTap: () => Navigator.pop(context, candidate.$1),
                    ),
                ],
              ),
      ),
    );
    if (selected == null) return;
    await repository.link(goal.id, targetType, selected);
    ref.read(refreshProvider.notifier).state++;
  }

  Future<String> _linkTitle(WidgetRef ref, EntityLinkEntry link) async {
    final database = ref.read(databaseProvider);
    if (link.targetType == 'TASK') {
      final row = await (database.select(database.tasks)
            ..where((value) => value.id.equals(link.targetId)))
          .getSingleOrNull();
      return row?.title ?? '任务已不存在';
    }
    final row = await (database.select(database.projects)
          ..where((value) => value.id.equals(link.targetId)))
        .getSingleOrNull();
    return row?.name ?? '项目已不存在';
  }

  Future<void> _addMilestone(
    BuildContext context,
    WidgetRef ref,
    GoalRepository repository,
  ) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('添加里程碑'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '里程碑名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('添加')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    await repository.addMilestone(goalId, value);
    ref.read(refreshProvider.notifier).state++;
  }
}
