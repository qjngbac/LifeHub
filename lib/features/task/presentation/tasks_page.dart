import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/relation_center_page.dart';
import 'package:lifehub/shared/ui/actionable_empty_state.dart';

Widget _taskChoiceGroup(BuildContext context, List<Widget> choices) {
  final minimumWidth = 24 + MediaQuery.textScalerOf(context).scale(13) * 3.2;
  return LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth - 18) / 4 >= minimumWidth
          ? 4
          : (constraints.maxWidth - 6) / 2 >= minimumWidth
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: choices
            .map((choice) => SizedBox(width: width, child: choice))
            .toList(),
      );
    },
  );
}

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key, this.projectId, this.title = '任务'});
  final String? projectId;
  final String title;

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  String? categoryFilter;
  int? priorityFilter;
  DateTimeRange? dueRangeFilter;
  final selectedIds = <String>{};

  bool get selecting => selectedIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = TaskRepository(ref.read(databaseProvider));
    return FutureBuilder<List<TaskEntry>>(
      future: repository.list(
        projectId: widget.projectId,
        category: categoryFilter,
        priority: priorityFilter,
        dueFrom: dueRangeFilter?.start,
        dueBefore: dueRangeFilter?.end.add(const Duration(days: 1)),
      ),
      builder: (context, snapshot) {
        final visibleTasks = snapshot.data ?? const <TaskEntry>[];
        final isAllSelected =
            visibleTasks.isNotEmpty &&
            visibleTasks.every((task) => selectedIds.contains(task.id));
        return Scaffold(
          appBar: AppBar(
            leading: selecting
                ? IconButton(
                    tooltip: '退出多选',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(selectedIds.clear),
                  )
                : null,
            title: Text(
              selecting ? '已选择 ${selectedIds.length} 项' : widget.title,
            ),
            actions: selecting
                ? [
                    IconButton(
                      tooltip: isAllSelected ? '取消全选' : '全选',
                      icon: Icon(
                        isAllSelected ? Icons.deselect : Icons.select_all,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isAllSelected) {
                            selectedIds.clear();
                          } else {
                            selectedIds.addAll(visibleTasks.map((t) => t.id));
                          }
                        });
                      },
                    ),
                    IconButton(
                      tooltip: '删除所选任务',
                      color: Theme.of(context).colorScheme.error,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          _deleteSelected(context, ref, repository),
                    ),
                    IconButton(
                      tooltip: '归档所选任务',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: () =>
                          _archiveSelected(context, ref, repository),
                    ),
                  ]
                : [
                    IconButton(
                      tooltip: '筛选任务',
                      icon: Badge(
                        isLabelVisible:
                            categoryFilter != null ||
                            priorityFilter != null ||
                            dueRangeFilter != null,
                        child: const Icon(Icons.filter_list),
                      ),
                      onPressed: () => _showFilters(context),
                    ),
                  ],
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'task_page_add_${widget.projectId}',
            onPressed: () => _editTask(context, ref, repository),
            child: const Icon(Icons.add),
          ),
          body: Builder(
            builder: (context) {
              if (snapshot.hasError) return const Center(child: Text('任务加载失败'));
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return ActionableEmptyState(
                  icon: Icons.task_alt,
                  title: '还没有任务',
                  message: '任务适合需要主动完成的事情；设置日期和时间段后，会在首页按时间展示。',
                  actionLabel: '创建第一个任务',
                  onAction: () => _editTask(context, ref, repository),
                );
              }
              final now = DateTime.now();
              final todayStart = DateTime(now.year, now.month, now.day);
              final overdueIds = snapshot.data!
                  .where((t) {
                    if (!TaskStatus.isActionable(t.status)) {
                      return false;
                    }
                    if (t.dueAt == null) return false;
                    final d = DateTime.fromMillisecondsSinceEpoch(
                      t.dueAt!,
                      isUtc: true,
                    ).toLocal();
                    return d.isBefore(todayStart);
                  })
                  .map((task) => task.id)
                  .toList();
              final overdueCount = overdueIds.length;
              final rows = _hierarchy(snapshot.data!);
              return Column(
                children: [
                  if (overdueCount > 0)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$overdueCount 项任务已逾期',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                            onPressed: () async {
                              final count = await repository
                                  .postponeOverdueTasks(
                                    DateTime.now(),
                                    taskIds: overdueIds,
                                  );
                              ref.read(refreshProvider.notifier).state++;
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('已将 $count 项逾期任务顺延到今天'),
                                  ),
                                );
                              }
                            },
                            child: const Text('一键顺延到今天'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final task = row.task;
                        final done = task.status == TaskStatus.done;
                        final lastInGroup =
                            index == rows.length - 1 ||
                            rows[index + 1].depth == 0;
                        final borderRadius = BorderRadius.vertical(
                          top: row.depth == 0
                              ? const Radius.circular(16)
                              : Radius.zero,
                          bottom: lastInGroup
                              ? const Radius.circular(16)
                              : Radius.zero,
                        );
                        return _SwipeableTaskCard(
                          key: ValueKey(task.id),
                          borderRadius: borderRadius,
                          padding: EdgeInsets.fromLTRB(
                            4,
                            row.depth == 0 ? 4 : 0,
                            4,
                            lastInGroup ? 4 : 0,
                          ),
                          enabled: !selecting,
                          isDone: done,
                          onComplete: () async {
                            await repository.setStatus(
                              task.id,
                              done ? TaskStatus.todo : TaskStatus.done,
                            );
                            ref.read(refreshProvider.notifier).state++;
                          },
                          onPostpone: () async {
                            final tomorrow = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            ).add(const Duration(days: 1));
                            final currentDue = task.dueAt == null
                                ? null
                                : DateTime.fromMillisecondsSinceEpoch(
                                    task.dueAt!,
                                    isUtc: true,
                                  ).toLocal();
                            final newDue = currentDue == null
                                ? tomorrow
                                : DateTime(
                                    tomorrow.year,
                                    tomorrow.month,
                                    tomorrow.day,
                                    currentDue.hour,
                                    currentDue.minute,
                                  );
                            await repository.postponeTask(task.id, newDue);
                            ref.read(refreshProvider.notifier).state++;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已顺延到明天')),
                              );
                            }
                          },
                          child: _TaskListItem(
                            task: task,
                            depth: row.depth,
                            borderRadius: borderRadius,
                            selecting: selecting,
                            selected: selectedIds.contains(task.id),
                            onLongPress: () => _toggleSelection(task.id),
                            onTap: () => selecting
                                ? _toggleSelection(task.id)
                                : _editTask(
                                    context,
                                    ref,
                                    repository,
                                    current: task,
                                  ),
                            onOptions: () => _showTaskOptionsSheet(
                              context,
                              ref,
                              repository,
                              task,
                              row.depth,
                            ),
                            onToggle: (value) async {
                              if (selecting) {
                                _toggleSelection(task.id);
                                return;
                              }
                              await repository.setStatus(
                                task.id,
                                value == true
                                    ? TaskStatus.done
                                    : TaskStatus.todo,
                              );
                              ref.read(refreshProvider.notifier).state++;
                              await refreshReminders(ref);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showTaskOptionsSheet(
    BuildContext context,
    WidgetRef ref,
    TaskRepository repository,
    TaskEntry task,
    int depth,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  _priorityBadge(task.priority),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改任务'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editTask(context, ref, repository, current: task);
              },
            ),
            if (depth < 4)
              ListTile(
                leading: const Icon(Icons.add_task_outlined),
                title: const Text('添加子任务'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editTask(context, ref, repository, parentTaskId: task.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.schedule_send_outlined),
              title: const Text('顺延到明天'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final now = DateTime.now();
                final tomorrow = DateTime(now.year, now.month, now.day)
                    .add(const Duration(days: 1));
                final currentDue = task.dueAt == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(task.dueAt!,
                            isUtc: true)
                        .toLocal();
                final newDue = currentDue == null
                    ? tomorrow
                    : DateTime(tomorrow.year, tomorrow.month, tomorrow.day,
                        currentDue.hour, currentDue.minute);
                await repository.postponeTask(task.id, newDue);
                ref.read(refreshProvider.notifier).state++;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已顺延到明天')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('关联关系'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RelationCenterPage(
                      initialEntity:
                          EntityReference(type: 'TASK', id: task.id),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('归档任务'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await repository.archive(task.id);
                ref.read(refreshProvider.notifier).state++;
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除任务', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (await _confirmDelete(context, task.title)) {
                  await repository.delete(task.id);
                  ref.read(refreshProvider.notifier).state++;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      selectedIds.contains(id) ? selectedIds.remove(id) : selectedIds.add(id);
    });
  }

  Future<void> _archiveSelected(
    BuildContext context,
    WidgetRef ref,
    TaskRepository repository,
  ) async {
    final count = selectedIds.length;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('归档 $count 个任务？'),
            content: const Text('子任务会按原有规则提升层级，归档内容可在归档中恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('归档'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await repository.archiveMany(selectedIds);
    if (!mounted) return;
    setState(selectedIds.clear);
    ref.read(refreshProvider.notifier).state++;
    await refreshReminders(ref);
  }

  Future<void> _deleteSelected(
    BuildContext context,
    WidgetRef ref,
    TaskRepository repository,
  ) async {
    final count = selectedIds.length;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('删除 $count 个任务？'),
            content: const Text('删除后不会出现在任务、搜索或归档中；未选择的子任务会自动提升层级。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await repository.deleteMany(selectedIds);
    if (!mounted) return;
    setState(selectedIds.clear);
    ref.read(refreshProvider.notifier).state++;
    await refreshReminders(ref);
  }

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    TaskRepository repository, {
    TaskEntry? current,
    String? parentTaskId,
  }) async {
    final titleController = TextEditingController(text: current?.title ?? '');
    String? titleError;
    var category = current?.category ?? TaskCategory.life;
    var priority = current?.priority ?? 0;
    final currentDue = current?.dueAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            current!.dueAt!,
            isUtc: true,
          ).toLocal();
    final currentStart = current?.startAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            current!.startAt!,
            isUtc: true,
          ).toLocal();
    var date = currentDue ?? currentStart ?? DateTime.now();
    var timed = currentStart != null;
    var startTime = TimeOfDay.fromDateTime(
      currentStart ?? DateTime(date.year, date.month, date.day, 9),
    );
    var endTime = TimeOfDay.fromDateTime(
      currentDue ?? DateTime(date.year, date.month, date.day, 10),
    );
    var repeating = current?.repeatRule != null;

    const categoryChips = [
      (TaskCategory.life, '生活', Icons.eco_outlined),
      (TaskCategory.study, '学习', Icons.school_outlined),
      (TaskCategory.work, '工作', Icons.work_outline),
      (TaskCategory.outdoor, '户外', Icons.landscape_outlined),
    ];

    const priorityChips = [
      (1, 'P1 紧急', Color(0xFFDC2626)),
      (2, 'P2 重要', Color(0xFFEA580C)),
      (3, 'P3 普通', Color(0xFF2563EB)),
      (0, 'P4 低优', Color(0xFF64748B)),
    ];

    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    final route = DialogRoute<TaskDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final weekday = weekdays[date.weekday - 1];
          return KeyboardSafeFormDialog(
            title: Text(current == null ? '新建任务' : '编辑任务'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: current == null,
                  onChanged: (_) {
                    if (titleError != null) setState(() => titleError = null);
                  },
                  decoration: InputDecoration(
                    labelText: '任务标题',
                    hintText: '写点要做的事情...',
                    errorText: titleError,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '分类',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _taskChoiceGroup(
                  context,
                  categoryChips.map((opt) {
                    final selected = category == opt.$1;
                    return ChoiceChip(
                      label: Text(opt.$2),
                      avatar: Icon(opt.$3, size: 14),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      labelStyle: const TextStyle(fontSize: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selected,
                      onSelected: (val) {
                        if (val) setState(() => category = opt.$1);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  '优先级',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _taskChoiceGroup(
                  context,
                  priorityChips.map((p) {
                    final selected = priority == p.$1;
                    final accent =
                        Theme.of(context).brightness == Brightness.dark
                        ? Color.lerp(p.$3, Colors.white, 0.3)!
                        : p.$3;
                    return ChoiceChip(
                      label: Text(
                        p.$2,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: accent,
                          fontSize: 13,
                        ),
                      ),
                      selectedColor: accent.withValues(alpha: 0.13),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      side: BorderSide(
                        color: selected
                            ? accent
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: selected ? 1.4 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selected,
                      onSelected: (val) {
                        if (val) setState(() => priority = p.$1);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      barrierDismissible: false,
                    );
                    if (selected != null) setState(() => date = selected);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '日期',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} 周$weekday',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '设置时间段',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            '默认当天 23:59 截止',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          value: timed,
                          onChanged: (value) => setState(() => timed = value),
                        ),
                        if (timed) ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final minimumWidth =
                                  60 +
                                  MediaQuery.textScalerOf(context).scale(13) *
                                      4;
                              final columns =
                                  (constraints.maxWidth - 8) / 2 >= minimumWidth
                                  ? 2
                                  : 1;
                              final width =
                                  (constraints.maxWidth - (columns - 1) * 8) /
                                  columns;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  SizedBox(
                                    width: width,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.schedule_outlined,
                                        size: 20,
                                      ),
                                      title: const Text(
                                        '开始时间',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        startTime.format(context),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onTap: () async {
                                        final value = await showTimePicker(
                                          context: context,
                                          initialTime: startTime,
                                          barrierDismissible: false,
                                        );
                                        if (value != null) {
                                          setState(() => startTime = value);
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: width,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.alarm_on_outlined,
                                        size: 20,
                                      ),
                                      title: const Text(
                                        '结束时间',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        endTime.format(context),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onTap: () async {
                                        final value = await showTimePicker(
                                          context: context,
                                          initialTime: endTime,
                                          barrierDismissible: false,
                                        );
                                        if (value != null && context.mounted) {
                                          setState(() => endTime = value);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '每天重复',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            '完成后生成下一次任务',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          value: repeating,
                          onChanged: (value) =>
                              setState(() => repeating = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    setState(() => titleError = '请输入任务标题');
                    return;
                  }
                  final start = timed
                      ? DateTime(
                          date.year,
                          date.month,
                          date.day,
                          startTime.hour,
                          startTime.minute,
                        )
                      : null;
                  final due = timed
                      ? DateTime(
                          date.year,
                          date.month,
                          date.day,
                          endTime.hour,
                          endTime.minute,
                        )
                      : DateTime(date.year, date.month, date.day, 23, 59);
                  Navigator.pop(
                    context,
                    TaskDraft(
                      title: title,
                      category: category,
                      priority: priority,
                      parentTaskId: parentTaskId ?? current?.parentTaskId,
                      projectId: current?.projectId ?? widget.projectId,
                      startAt: start,
                      dueAt: due,
                      repeatRule: repeating ? 'DAILY' : null,
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    final draft = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    titleController.dispose();
    if (draft == null) return;
    if (current == null) {
      await repository.create(draft);
    } else {
      await repository.update(current.id, draft);
    }
    if (!mounted) return;
    ref.read(refreshProvider.notifier).state++;
    await refreshReminders(ref);
  }

  Future<void> _showFilters(BuildContext context) async {
    var category = categoryFilter;
    var priority = priorityFilter;
    var dueRange = dueRangeFilter;

    const catOptions = [
      (null, '全部分类'),
      (TaskCategory.study, '学习 📚'),
      (TaskCategory.work, '工作 💼'),
      (TaskCategory.life, '生活 🌿'),
      (TaskCategory.outdoor, '户外 🏕️'),
    ];

    const priorityOptions = [
      (null, '全部'),
      (1, 'P1 紧急'),
      (2, 'P2 重要'),
      (3, 'P3 普通'),
      (0, 'P4 低优'),
    ];

    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    '筛选任务',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '分类',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: catOptions.map((opt) {
                    final selected = category == opt.$1;
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: selected,
                      onSelected: (val) {
                        if (val) setSheetState(() => category = opt.$1);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  '优先级',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: priorityOptions.map((opt) {
                    final selected = priority == opt.$1;
                    return ChoiceChip(
                      label: Text(opt.$2),
                      selected: selected,
                      onSelected: (val) {
                        if (val) setSheetState(() => priority = opt.$1);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Text(
                  '截止日期范围',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final selected = await showDateRangePicker(
                      context: context,
                      initialDateRange: dueRange,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) {
                      setSheetState(() => dueRange = selected);
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.6),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dueRange == null
                                ? '全部日期范围'
                                : '${dueRange!.start.year}-${dueRange!.start.month}-${dueRange!.start.day} 至 ${dueRange!.end.year}-${dueRange!.end.month}-${dueRange!.end.day}',
                            style: TextStyle(
                              fontSize: 13,
                              color: dueRange == null
                                  ? Theme.of(context).colorScheme.outline
                                  : null,
                              fontWeight: dueRange == null
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (dueRange != null)
                          GestureDetector(
                            onTap: () =>
                                setSheetState(() => dueRange = null),
                            child: const Icon(Icons.close, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        category = null;
                        priority = null;
                        dueRange = null;
                        Navigator.pop(context, true);
                      },
                      child: const Text('重置条件'),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('应用筛选'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        categoryFilter = category;
        priorityFilter = priority;
        dueRangeFilter = dueRange;
      });
    }
  }
}

class _TaskListItem extends StatefulWidget {
  const _TaskListItem({
    required this.task,
    required this.depth,
    required this.borderRadius,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onOptions,
    required this.onToggle,
  });

  final TaskEntry task;
  final int depth;
  final BorderRadius borderRadius;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOptions;
  final ValueChanged<bool?> onToggle;

  @override
  State<_TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<_TaskListItem> {
  bool titleExpanded = false;

  @override
  void didUpdateWidget(covariant _TaskListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.title != widget.task.title) titleExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final colors = Theme.of(context).colorScheme;
    final done = task.status == TaskStatus.done;
    final titleStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(
      fontSize: 15.5,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: done ? colors.outline : colors.onSurface,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    final metadataStyle = TextStyle(
      fontSize: 12,
      color: done ? colors.outline : colors.onSurfaceVariant,
    );
    final due = _taskDueLabel(task);
    final overdue =
        task.dueAt != null &&
        TaskStatus.isActionable(task.status) &&
        task.dueAt! < DateTime.now().millisecondsSinceEpoch;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: widget.borderRadius,
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      color: widget.selected
          ? colors.secondaryContainer
          : done
          ? colors.surfaceContainerLowest.withValues(alpha: 0.85)
          : colors.surface,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12 + (widget.depth * 8).clamp(0, 32).toDouble(),
            widget.depth == 0 ? 8 : 5,
            12,
            widget.depth == 0 ? 10 : 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 36,
                    height: 40,
                    child: Checkbox(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      value: widget.selecting ? widget.selected : done,
                      onChanged: widget.onToggle,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final painter = TextPainter(
                          text: TextSpan(text: task.title, style: titleStyle),
                          maxLines: 1,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout(maxWidth: constraints.maxWidth);
                        final canExpand = painter.didExceedMaxLines;
                        painter.dispose();
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                child: Text(
                                  task.title,
                                  style: titleStyle,
                                  maxLines: titleExpanded ? null : 1,
                                  overflow: titleExpanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (canExpand && !widget.selecting)
                              SizedBox(
                                width: 28,
                                height: 40,
                                child: IconButton(
                                  tooltip: titleExpanded ? '收起任务标题' : '展开任务标题',
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  color: colors.outline,
                                  onPressed: () => setState(
                                    () => titleExpanded = !titleExpanded,
                                  ),
                                  icon: Icon(
                                    titleExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (!widget.selecting)
                    SizedBox(
                      width: 32,
                      height: 40,
                      child: IconButton(
                        tooltip: '任务操作',
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_horiz_rounded, size: 20),
                        color: colors.outline,
                        onPressed: widget.onOptions,
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _priorityBadge(task.priority),
                  Text(_taskCategoryLabel(task.category), style: metadataStyle),
                  if (due.isNotEmpty)
                    Tooltip(
                      message: _taskFullDueLabel(task),
                      child: Text(
                        '${overdue ? '逾期 · ' : ''}$due',
                        style: overdue
                            ? metadataStyle.copyWith(color: colors.error)
                            : metadataStyle,
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

class _TaskRow {
  const _TaskRow(this.task, this.depth);
  final TaskEntry task;
  final int depth;
}

Future<bool> _confirmDelete(BuildContext context, String title) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('删除任务？'),
          content: Text('“$title”删除后不会出现在搜索或归档中。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}

List<_TaskRow> _hierarchy(List<TaskEntry> tasks) {
  final ids = tasks.map((task) => task.id).toSet();
  final children = <String, List<TaskEntry>>{};
  final roots = <TaskEntry>[];
  for (final task in tasks) {
    if (task.parentTaskId == null || !ids.contains(task.parentTaskId)) {
      roots.add(task);
    } else {
      children.putIfAbsent(task.parentTaskId!, () => []).add(task);
    }
  }
  final rows = <_TaskRow>[];
  void append(TaskEntry task, int depth, Set<String> path) {
    if (!path.add(task.id)) return;
    rows.add(_TaskRow(task, depth));
    for (final child in children[task.id] ?? const <TaskEntry>[]) {
      append(child, depth + 1, {...path});
    }
  }

  for (final task in roots) {
    append(task, 0, <String>{});
  }
  return rows;
}

String _statusLabel(String status) => switch (status) {
      TaskStatus.todo => '待办',
      TaskStatus.inProgress => '进行中',
      TaskStatus.done => '已完成',
      TaskStatus.canceled => '已取消',
      _ => status,
    };

String _taskCategoryLabel(String category) => switch (category) {
  TaskCategory.study => '学习',
  TaskCategory.work => '工作',
  TaskCategory.outdoor => '户外',
  _ => '生活',
};

String _taskDueLabel(TaskEntry task) {
  if (task.dueAt != null) {
    final due = DateTime.fromMillisecondsSinceEpoch(
      task.dueAt!,
      isUtc: true,
    ).toLocal();
    final start = task.startAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            task.startAt!,
            isUtc: true,
          ).toLocal();
    if (start == null) {
      return due.hour == 23 && due.minute == 59
          ? _taskDateLabel(due)
          : '${_taskDateLabel(due)} ${_clock(due)}';
    }
    final sameDay =
        start.year == due.year &&
        start.month == due.month &&
        start.day == due.day;
    return sameDay
        ? '${_taskDateLabel(due)} ${_clock(start)}–${_clock(due)}'
        : '${_taskDateLabel(start)} ${_clock(start)}–${_taskDateLabel(due)} ${_clock(due)}';
  }
  return task.status == TaskStatus.done ? '' : _statusLabel(task.status);
}

String _taskDateLabel(DateTime date) => date.year == DateTime.now().year
    ? '${date.month}月${date.day}日'
    : '${date.year}/${date.month}/${date.day}';

String _taskFullDueLabel(TaskEntry task) {
  if (task.dueAt == null) return _taskDueLabel(task);
  String fullDate(int timestamp) {
    final value = DateTime.fromMillisecondsSinceEpoch(
      timestamp,
      isUtc: true,
    ).toLocal();
    return '${value.year}/${value.month}/${value.day} ${_clock(value)}';
  }

  return task.startAt == null
      ? '截止 ${fullDate(task.dueAt!)}'
      : '${fullDate(task.startAt!)}–${fullDate(task.dueAt!)}';
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Widget _priorityBadge(int priority) {
  final (color, bg, border, text) = switch (priority) {
    1 => (
        const Color(0xFFDC2626),
        const Color(0xFFFEE2E2),
        const Color(0xFFFCA5A5),
        'P1',
      ),
    2 => (
        const Color(0xFFEA580C),
        const Color(0xFFFFEDD5),
        const Color(0xFFFDBA74),
        'P2',
      ),
    3 => (
        const Color(0xFF2563EB),
        const Color(0xFFDBEAFE),
        const Color(0xFF93C5FD),
        'P3',
      ),
    _ => (
        const Color(0xFF64748B),
        const Color(0xFFF1F5F9),
        const Color(0xFFCBD5E1),
        'P4',
      ),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border.withValues(alpha: 0.8), width: 0.8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class _SwipeableTaskCard extends StatefulWidget {
  const _SwipeableTaskCard({
    super.key,
    required this.enabled,
    required this.onComplete,
    required this.onPostpone,
    required this.isDone,
    required this.child,
    required this.borderRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  final bool enabled;
  final Future<void> Function() onComplete;
  final Future<void> Function() onPostpone;
  final bool isDone;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  State<_SwipeableTaskCard> createState() => _SwipeableTaskCardState();
}

class _SwipeableTaskCardState extends State<_SwipeableTaskCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Animation<double>? _anim;
  double _dragOffset = 0.0;
  bool _hapticFired = false;

  static const double _rightTriggerThreshold = 72.0;
  static const double _leftTriggerThreshold = 80.0;
  static const double _rightNaturalLimit = 135.0;
  static const double _leftNaturalLimit = 165.0;
  static const double _rightMaxLimit = 175.0;
  static const double _leftMaxLimit = 215.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (_anim != null) {
          setState(() => _dragOffset = _anim!.value);
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateBack() {
    _anim = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Padding(
        padding: widget.padding,
        child: widget.child,
      );
    }

    final isSwipeRight = _dragOffset > 0;
    final isSwipeLeft = _dragOffset < 0;
    final progress = (_dragOffset.abs() / 45.0).clamp(0.0, 1.0);

    return Padding(
      padding: widget.padding,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            final delta = details.primaryDelta ?? 0;
            var next = _dragOffset + delta;

            final naturalLimit =
                next > 0 ? _rightNaturalLimit : _leftNaturalLimit;
            final maxLimit = next > 0 ? _rightMaxLimit : _leftMaxLimit;

            if (next.abs() > naturalLimit) {
              final excess = next.abs() - naturalLimit;
              final damped = naturalLimit + excess * 0.35;
              final capped = damped.clamp(0.0, maxLimit);
              next = next > 0 ? capped : -capped;
            }
            _dragOffset = next;

            final triggerThreshold = _dragOffset > 0
                ? _rightTriggerThreshold
                : _leftTriggerThreshold;
            if (_dragOffset.abs() >= triggerThreshold && !_hapticFired) {
              HapticFeedback.lightImpact();
              _hapticFired = true;
            } else if (_dragOffset.abs() < triggerThreshold) {
              _hapticFired = false;
            }
          });
        },
        onHorizontalDragEnd: (details) async {
          final velocity = details.primaryVelocity ?? 0;
          final triggeredRight = _dragOffset >= _rightTriggerThreshold ||
              (velocity > 350 && _dragOffset > 25);
          final triggeredLeft = _dragOffset <= -_leftTriggerThreshold ||
              (velocity < -350 && _dragOffset < -25);

          if (triggeredRight) {
            HapticFeedback.mediumImpact();
            _animateBack();
            await widget.onComplete();
          } else if (triggeredLeft) {
            HapticFeedback.mediumImpact();
            _animateBack();
            await widget.onPostpone();
          } else {
            _animateBack();
          }
        },
        onHorizontalDragCancel: _animateBack,
        child: Stack(
          children: [
            if (_dragOffset != 0)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: isSwipeRight
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF97316),
                    borderRadius: widget.borderRadius,
                  ),
                  alignment: isSwipeRight
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  padding: EdgeInsets.only(
                    left: isSwipeRight ? 18 : 0,
                    right: isSwipeLeft ? 18 : 0,
                  ),
                  child: Opacity(
                    opacity: (progress * 1.2).clamp(0.0, 1.0),
                    child: isSwipeRight
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.isDone
                                    ? Icons.restart_alt_rounded
                                    : Icons.check_circle_outline,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.isDone ? '重置' : '完成',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '顺延到明天',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.schedule_send_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
