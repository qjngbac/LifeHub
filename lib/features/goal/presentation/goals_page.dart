import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/goal/presentation/goal_detail_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = GoalRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('目标')),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建目标',
        onPressed: () => _create(context, ref, repository),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<GoalEntry>>(
        future: repository.list(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('目标加载失败'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final goals = snapshot.data!;
          if (goals.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('还没有目标'),
                  SizedBox(height: 8),
                  Text('目标用于连接长期方向、项目、任务与习惯。'),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: goals.length,
            itemBuilder: (context, index) => _GoalCard(
              goal: goals[index],
              repository: repository,
              onOpen: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GoalDetailPage(goalId: goals[index].id),
                  ),
                );
                ref.read(refreshProvider.notifier).state++;
              },
              onDelete: () async {
                await repository.delete(goals[index].id);
                ref.read(refreshProvider.notifier).state++;
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    GoalRepository repository,
  ) async {
    final name = TextEditingController();
    final description = TextEditingController();
    var mode = GoalProgressMode.milestone;
    final draft = await showDialog<GoalDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title: const Text('创建目标'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '目标名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: '说明（可选）'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: '进度方式'),
                items: const [
                  DropdownMenuItem(
                      value: GoalProgressMode.milestone, child: Text('按里程碑')),
                  DropdownMenuItem(
                      value: GoalProgressMode.task, child: Text('按关联任务')),
                  DropdownMenuItem(
                      value: GoalProgressMode.project, child: Text('按关联项目')),
                  DropdownMenuItem(
                      value: GoalProgressMode.manual, child: Text('手工进度')),
                ],
                onChanged: (value) =>
                    setDialogState(() => mode = value ?? mode),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                GoalDraft(
                  name: name.text,
                  description: description.text,
                  progressMode: mode,
                  manualProgress: mode == GoalProgressMode.manual ? 0 : null,
                ),
              ),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (draft == null) return;
    try {
      final goal = await repository.create(draft);
      ref.read(refreshProvider.notifier).state++;
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailPage(goalId: goal.id),
          ),
        );
      }
    } on ArgumentError {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请填写有效的目标名称')));
      }
    }
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.repository,
    required this.onOpen,
    required this.onDelete,
  });

  final GoalEntry goal;
  final GoalRepository repository;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => FutureBuilder<double>(
        future: repository.progress(goal.id),
        builder: (context, snapshot) {
          final progress = snapshot.data ?? 0;
          return Card(
            child: ListTile(
              onTap: onOpen,
              leading: CircleAvatar(
                child: Text('${(progress * 100).round()}%'),
              ),
              title: Text(goal.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (goal.targetAt != null)
                    Text(
                      '目标日期 ${DateFormat('yyyy-MM-dd').format(
                        DateTime.fromMillisecondsSinceEpoch(
                          goal.targetAt!,
                          isUtc: true,
                        ).toLocal(),
                      )}',
                    ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: progress),
                ],
              ),
              trailing: PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (_) => onDelete(),
              ),
            ),
          );
        },
      );
}
