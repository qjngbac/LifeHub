import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/relation_center_page.dart';
import 'package:lifehub/shared/ui/actionable_empty_state.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: () => setState(selectedIds.clear),
              )
            : null,
        title: Text(selecting ? '已选择 ${selectedIds.length} 项' : widget.title),
        actions: selecting
            ? [
                IconButton(
                  tooltip: '删除所选任务',
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteSelected(context, ref, repository),
                ),
                IconButton(
                  tooltip: '归档所选任务',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () => _archiveSelected(context, ref, repository),
                ),
              ]
            : [
                IconButton(
                  tooltip: '筛选任务',
                  icon: Badge(
                    isLabelVisible: categoryFilter != null ||
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
      body: FutureBuilder<List<TaskEntry>>(
        future: repository.list(
          projectId: widget.projectId,
          category: categoryFilter,
          priority: priorityFilter,
          dueFrom: dueRangeFilter?.start,
          dueBefore: dueRangeFilter?.end.add(const Duration(days: 1)),
        ),
        builder: (context, snapshot) {
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
          final rows = _hierarchy(snapshot.data!);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final task = row.task;
              final done = task.status == TaskStatus.done;
              return Padding(
                padding: EdgeInsets.only(left: row.depth * 20.0),
                child: Dismissible(
                  key: ValueKey(task.id),
                  direction: selecting
                      ? DismissDirection.none
                      : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Icon(Icons.archive_outlined),
                  ),
                  confirmDismiss: (_) async =>
                      await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          title: const Text('归档任务？'),
                          content: Text(task.title),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('归档')),
                          ],
                        ),
                      ) ??
                      false,
                  onDismissed: (_) async {
                    await repository.archive(task.id);
                    ref.read(refreshProvider.notifier).state++;
                  },
                  child: Card(
                    color: selectedIds.contains(task.id)
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    child: ListTile(
                      selected: selectedIds.contains(task.id),
                      title: Text(task.title,
                          style: done
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough)
                              : null),
                      subtitle: Text(_taskSubtitle(task)),
                      onLongPress: () => _toggleSelection(task.id),
                      onTap: () => selecting
                          ? _toggleSelection(task.id)
                          : _editTask(context, ref, repository, current: task),
                      trailing: SizedBox(
                        width: selecting ? 48 : 96,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!selecting)
                              PopupMenuButton<String>(
                                tooltip: '任务操作',
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'relation',
                                    child: Text('关联关系'),
                                  ),
                                  const PopupMenuItem(
                                      value: 'edit', child: Text('编辑')),
                                  if (row.depth < 4)
                                    const PopupMenuItem(
                                        value: 'subtask', child: Text('添加子任务')),
                                  const PopupMenuItem(
                                      value: 'archive', child: Text('归档')),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                                onSelected: (value) async {
                                  if (value == 'relation') {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RelationCenterPage(
                                          initialEntity: EntityReference(
                                            type: 'TASK',
                                            id: task.id,
                                          ),
                                        ),
                                      ),
                                    );
                                  } else if (value == 'edit') {
                                    await _editTask(context, ref, repository,
                                        current: task);
                                  } else if (value == 'subtask') {
                                    await _editTask(context, ref, repository,
                                        parentTaskId: task.id);
                                  } else if (value == 'archive') {
                                    await repository.archive(task.id);
                                    ref.read(refreshProvider.notifier).state++;
                                  } else if (await _confirmDelete(
                                      context, task.title)) {
                                    await repository.delete(task.id);
                                    ref.read(refreshProvider.notifier).state++;
                                  }
                                },
                              ),
                            Checkbox(
                              value: selecting
                                  ? selectedIds.contains(task.id)
                                  : done,
                              onChanged: (value) async {
                                if (selecting) {
                                  _toggleSelection(task.id);
                                  return;
                                }
                                await repository.setStatus(
                                    task.id,
                                    value == true
                                        ? TaskStatus.done
                                        : TaskStatus.todo);
                                ref.read(refreshProvider.notifier).state++;
                                await refreshReminders(ref);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
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
    var category = current?.category ?? TaskCategory.life;
    var priority = current?.priority ?? 0;
    final currentDue = current?.dueAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(current!.dueAt!, isUtc: true)
            .toLocal();
    final currentStart = current?.startAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(current!.startAt!, isUtc: true)
            .toLocal();
    var date = currentDue ?? currentStart ?? DateTime.now();
    var timed = currentStart != null;
    var startTime = TimeOfDay.fromDateTime(
        currentStart ?? DateTime(date.year, date.month, date.day, 9));
    var endTime = TimeOfDay.fromDateTime(
        currentDue ?? DateTime(date.year, date.month, date.day, 10));
    var repeating = current?.repeatRule != null;
    final draft = await showDialog<TaskDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => KeyboardSafeFormDialog(
          title: Text(current == null ? '新建任务' : '编辑任务'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '任务标题'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: '分类'),
              items: const [
                DropdownMenuItem(value: TaskCategory.study, child: Text('学习')),
                DropdownMenuItem(value: TaskCategory.work, child: Text('工作')),
                DropdownMenuItem(value: TaskCategory.life, child: Text('生活')),
                DropdownMenuItem(
                    value: TaskCategory.outdoor, child: Text('户外')),
              ],
              onChanged: (value) =>
                  setState(() => category = value ?? category),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('优先级'),
              Expanded(
                child: Slider(
                  value: priority.toDouble(),
                  min: 0,
                  max: 4,
                  divisions: 4,
                  label: '$priority',
                  onChanged: (value) =>
                      setState(() => priority = value.round()),
                ),
              ),
            ]),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('任务日期'),
              subtitle: Text('${date.year}-${date.month}-${date.day}'),
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
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('设置时间段'),
              subtitle: const Text('关闭时默认当天 23:59 截止'),
              value: timed,
              onChanged: (value) => setState(() => timed = value),
            ),
            if (timed)
              Row(children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始'),
                    subtitle: Text(startTime.format(context)),
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
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束'),
                    subtitle: Text(endTime.format(context)),
                    onTap: () async {
                      final value = await showTimePicker(
                        context: context,
                        initialTime: endTime,
                        barrierDismissible: false,
                      );
                      if (value != null) setState(() => endTime = value);
                    },
                  ),
                ),
              ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('每天重复'),
              value: repeating,
              onChanged: (value) => setState(() => repeating = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                final startAt = timed
                    ? DateTime(date.year, date.month, date.day, startTime.hour,
                        startTime.minute)
                    : null;
                final dueAt = timed
                    ? DateTime(date.year, date.month, date.day, endTime.hour,
                        endTime.minute)
                    : DateTime(date.year, date.month, date.day, 23, 59);
                if (startAt != null && !dueAt.isAfter(startAt)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('结束时间必须晚于开始时间')),
                  );
                  return;
                }
                Navigator.pop(
                    context,
                    TaskDraft(
                      title: titleController.text.trim(),
                      category: category,
                      priority: priority,
                      dueAt: dueAt,
                      startAt: startAt,
                      projectId: widget.projectId ?? current?.projectId,
                      parentTaskId: parentTaskId ?? current?.parentTaskId,
                      repeatRule: repeating ? 'FREQ=DAILY;INTERVAL=1' : null,
                    ));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    if (draft == null) return;
    if (current == null) {
      await repository.create(draft);
    } else {
      await repository.update(current.id, draft);
    }
    ref.read(refreshProvider.notifier).state++;
    await refreshReminders(ref);
  }

  Future<void> _showFilters(BuildContext context) async {
    var category = categoryFilter;
    var priority = priorityFilter;
    var dueRange = dueRangeFilter;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('筛选任务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部分类')),
                  DropdownMenuItem(
                      value: TaskCategory.study, child: Text('学习')),
                  DropdownMenuItem(value: TaskCategory.work, child: Text('工作')),
                  DropdownMenuItem(value: TaskCategory.life, child: Text('生活')),
                  DropdownMenuItem(
                      value: TaskCategory.outdoor, child: Text('户外')),
                ],
                onChanged: (value) => setSheetState(() => category = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部优先级')),
                  ...List.generate(
                      5,
                      (value) => DropdownMenuItem(
                          value: value, child: Text('优先级 $value'))),
                ],
                onChanged: (value) => setSheetState(() => priority = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('截止日期范围'),
                subtitle: Text(dueRange == null
                    ? '全部日期'
                    : '${dueRange!.start.year}-${dueRange!.start.month}-${dueRange!.start.day}'
                        ' 至 ${dueRange!.end.year}-${dueRange!.end.month}-${dueRange!.end.day}'),
                trailing: dueRange == null
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        onPressed: () => setSheetState(() => dueRange = null),
                        icon: const Icon(Icons.clear)),
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
              ),
              Row(children: [
                TextButton(
                  onPressed: () {
                    category = null;
                    priority = null;
                    dueRange = null;
                    Navigator.pop(context, true);
                  },
                  child: const Text('清除'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('应用'),
                ),
              ]),
            ]),
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

String _taskSubtitle(TaskEntry task) {
  final labels = <String>[_statusLabel(task.status)];
  if (task.dueAt != null) {
    final due =
        DateTime.fromMillisecondsSinceEpoch(task.dueAt!, isUtc: true).toLocal();
    final start = task.startAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(task.startAt!, isUtc: true)
            .toLocal();
    final overdue =
        due.isBefore(DateTime.now()) && task.status != TaskStatus.done;
    final time = start == null
        ? '${due.month}月${due.day}日 ${_clock(due)}'
        : '${due.month}月${due.day}日 ${_clock(start)}–${_clock(due)}';
    labels.add('${overdue ? '已逾期 · ' : ''}$time');
  }
  labels.add('优先级 ${task.priority}');
  return labels.join(' · ');
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
