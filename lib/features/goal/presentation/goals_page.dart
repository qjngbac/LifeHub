import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/goal/data/goal_repository.dart';
import 'package:lifehub/features/goal/presentation/goal_detail_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  int _filterIndex = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = GoalRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('目标')),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建目标',
        onPressed: () => _create(context, ref, repository),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('进行中')),
                  ButtonSegment(value: 1, label: Text('已达成')),
                  ButtonSegment(value: 2, label: Text('全部')),
                ],
                selected: {_filterIndex},
                onSelectionChanged: (val) =>
                    setState(() => _filterIndex = val.first),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GoalEntry>>(
              future: repository.list(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('目标加载失败'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allGoals = snapshot.data!;
                if (allGoals.isEmpty) {
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
                return FutureBuilder<List<(GoalEntry, double)>>(
                  future: Future.wait(
                    allGoals.map(
                      (g) async => (g, await repository.progress(g.id)),
                    ),
                  ),
                  builder: (context, progressSnapshot) {
                    if (!progressSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final allWithProgress = progressSnapshot.data!;
                    final totalGoals = allWithProgress.length;
                    final completedGoals =
                        allWithProgress.where((i) => i.$2 >= 1.0).length;
                    final activeGoals = totalGoals - completedGoals;
                    final avgProgress = totalGoals == 0
                        ? 0
                        : ((allWithProgress.fold<double>(
                                    0.0, (acc, item) => acc + item.$2) /
                                totalGoals) *
                            100)
                            .round();

                    final goalList = allWithProgress.where((item) {
                      final progress = item.$2;
                      if (_filterIndex == 0) return progress < 1.0;
                      if (_filterIndex == 1) return progress >= 1.0;
                      return true;
                    }).toList();

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: goalList.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildGoalOverviewDashboard(
                            activeGoals: activeGoals,
                            completedGoals: completedGoals,
                            avgProgress: avgProgress,
                          );
                        }
                        if (goalList.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text(
                                _filterIndex == 1
                                    ? '还没有达成任何目标，继续加油！'
                                    : '暂无符合条件的目标',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                          );
                        }
                        final (goal, progress) = goalList[index - 1];
                        return _GoalCard(
                          goal: goal,
                          progress: progress,
                          repository: repository,
                          onOpen: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GoalDetailPage(goalId: goal.id),
                              ),
                            );
                            ref.read(refreshProvider.notifier).state++;
                          },
                          onDelete: () async {
                            await repository.delete(goal.id);
                            ref.read(refreshProvider.notifier).state++;
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalOverviewDashboard({
    required int activeGoals,
    required int completedGoals,
    required int avgProgress,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            _buildGoalStatItem(
              label: '进行中',
              count: '$activeGoals',
              color: colorScheme.primary,
              icon: Icons.flag_outlined,
              isSelected: _filterIndex == 0,
              onTap: () => setState(() => _filterIndex = 0),
            ),
            Container(
              width: 0.8,
              height: 28,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            _buildGoalStatItem(
              label: '已达成',
              count: '$completedGoals',
              color: Colors.amber.shade700,
              icon: Icons.emoji_events_outlined,
              isSelected: _filterIndex == 1,
              onTap: () => setState(() => _filterIndex = 1),
            ),
            Container(
              width: 0.8,
              height: 28,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            _buildGoalStatItem(
              label: '平均进度',
              count: '$avgProgress%',
              color: Colors.green.shade700,
              icon: Icons.pie_chart_outline,
              isSelected: false,
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalStatItem({
    required String label,
    required String count,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
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

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    GoalRepository repository,
  ) async {
    final name = TextEditingController();
    final description = TextEditingController();
    var mode = GoalProgressMode.milestone;
    DateTime? targetDate;
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('目标达成日期（可选）'),
                subtitle: Text(targetDate == null
                    ? '未设置'
                    : DateFormat('yyyy-MM-dd').format(targetDate!)),
                trailing: targetDate != null
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setDialogState(() => targetDate = null),
                      )
                    : null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: targetDate ??
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => targetDate = picked);
                  }
                },
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
                  targetAt: targetDate,
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
    required this.progress,
    required this.repository,
    required this.onOpen,
    required this.onDelete,
  });

  final GoalEntry goal;
  final double progress;
  final GoalRepository repository;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDone = progress >= 1.0;
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: CircleAvatar(
          backgroundColor: isDone
              ? Colors.amber.shade100
              : Theme.of(context).colorScheme.primaryContainer,
          child: isDone
              ? const Icon(Icons.emoji_events, color: Colors.amber)
              : Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(goal.name)),
            if (isDone)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '已达成',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (goal.targetAt != null) ...[
              const SizedBox(height: 4),
              _buildCountdown(context, goal.targetAt!, progress),
            ],
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              color: isDone ? Colors.amber : null,
            ),
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
  }

  Widget _buildCountdown(
      BuildContext context, int targetAtMs, double progress) {
    final targetDate =
        DateTime.fromMillisecondsSinceEpoch(targetAtMs, isUtc: true).toLocal();
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfTarget =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final diffDays = startOfTarget.difference(startOfToday).inDays;

    final String countdownText;
    final Color countdownColor;
    if (progress >= 1.0) {
      countdownText = '已达成';
      countdownColor = Colors.amber.shade800;
    } else if (diffDays < 0) {
      countdownText = '已逾期 ${-diffDays} 天';
      countdownColor = Theme.of(context).colorScheme.error;
    } else if (diffDays == 0) {
      countdownText = '今天截止';
      countdownColor = Colors.orange.shade800;
    } else {
      countdownText = '倒计时 $diffDays 天';
      countdownColor = Theme.of(context).colorScheme.primary;
    }

    return Row(
      children: [
        Icon(Icons.flag_circle_outlined,
            size: 13, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(
          '目标: ${DateFormat('yyyy-MM-dd').format(targetDate)} · ',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
        Text(
          countdownText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: countdownColor,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
