import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/project/data/project_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => KeyboardSafeFormDialog(
      title: Text(title),
      body: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

Future<void> createTaskDialog(
  BuildContext context,
  WidgetRef ref, {
  DateTime? dueOn,
}) async {
  final initial = dueOn ?? DateTime.now();
  final title = TextEditingController();
  var date = DateTime(initial.year, initial.month, initial.day);
  var timed = false;
  var startTime = const TimeOfDay(hour: 9, minute: 0);
  var endTime = const TimeOfDay(hour: 10, minute: 0);
  final draft = await showDialog<TaskDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => KeyboardSafeFormDialog(
        title: const Text('新建任务'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(labelText: '任务标题'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('日期'),
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
            subtitle: const Text('不设置时间时，默认在当天完成'),
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
                    if (value != null) setState(() => startTime = value);
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
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              final start = timed
                  ? DateTime(date.year, date.month, date.day, startTime.hour,
                      startTime.minute)
                  : null;
              final end = timed
                  ? DateTime(date.year, date.month, date.day, endTime.hour,
                      endTime.minute)
                  : DateTime(date.year, date.month, date.day, 23, 59);
              if (start != null && !end.isAfter(start)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('结束时间必须晚于开始时间')),
                );
                return;
              }
              Navigator.pop(
                context,
                TaskDraft(
                  title: title.text.trim(),
                  startAt: start,
                  dueAt: end,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  if (draft == null) return;
  await TaskRepository(ref.read(databaseProvider)).create(draft);
  ref.read(refreshProvider.notifier).state++;
  await refreshReminders(ref);
  if (context.mounted) _success(context, '任务已创建');
}

Future<void> editTaskDialog(
  BuildContext context,
  WidgetRef ref,
  TaskEntry task,
) async {
  final repository = TaskRepository(ref.read(databaseProvider));
  final title = TextEditingController(text: task.title);
  final storedEnd = task.dueAt == null
      ? DateTime.now()
      : DateTime.fromMillisecondsSinceEpoch(task.dueAt!, isUtc: true).toLocal();
  final storedStart = task.startAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(task.startAt!, isUtc: true)
          .toLocal();
  var date = DateTime(storedEnd.year, storedEnd.month, storedEnd.day);
  var timed = storedStart != null;
  var startTime = TimeOfDay.fromDateTime(
      storedStart ?? DateTime(date.year, date.month, date.day, 9));
  var endTime = TimeOfDay.fromDateTime(storedEnd);
  final draft = await showDialog<TaskDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => KeyboardSafeFormDialog(
        title: const Text('编辑任务'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(labelText: '任务标题'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('日期'),
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
                    if (value != null) setState(() => startTime = value);
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
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              final start = timed
                  ? DateTime(date.year, date.month, date.day, startTime.hour,
                      startTime.minute)
                  : null;
              final end = timed
                  ? DateTime(date.year, date.month, date.day, endTime.hour,
                      endTime.minute)
                  : DateTime(date.year, date.month, date.day, 23, 59);
              if (start != null && !end.isAfter(start)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('结束时间必须晚于开始时间')),
                );
                return;
              }
              Navigator.pop(
                context,
                TaskDraft(
                  title: title.text.trim(),
                  description: task.description,
                  category: task.category,
                  priority: task.priority,
                  startAt: start,
                  dueAt: end,
                  projectId: task.projectId,
                  parentTaskId: task.parentTaskId,
                  repeatRule: task.repeatRule,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  if (draft == null) return;
  await repository.update(task.id, draft);
  ref.read(refreshProvider.notifier).state++;
  await refreshReminders(ref);
}

Future<void> createProjectDialog(BuildContext context, WidgetRef ref) async {
  final name = await promptText(context, title: '新建项目', label: '项目名称');
  if (name == null || !context.mounted) return;
  await ProjectRepository(ref.read(databaseProvider))
      .create(ProjectDraft(name: name));
  ref.read(refreshProvider.notifier).state++;
  if (context.mounted) _success(context, '项目已创建');
}

Future<void> createListDialog(BuildContext context, WidgetRef ref,
    {String? projectId}) async {
  final name = await promptText(context, title: '新建清单', label: '清单名称');
  if (name == null || !context.mounted) return;
  await ListRepository(ref.read(databaseProvider))
      .createList(name, projectId: projectId);
  ref.read(refreshProvider.notifier).state++;
  if (context.mounted) _success(context, '清单已创建');
}

Future<void> createHabitDialog(BuildContext context, WidgetRef ref) async {
  final name = await promptText(context, title: '新建习惯', label: '习惯名称');
  if (name == null || !context.mounted) return;
  await HabitRepository(ref.read(databaseProvider))
      .create(HabitDraft(name: name));
  ref.read(refreshProvider.notifier).state++;
  if (context.mounted) _success(context, '习惯已创建');
}

Future<void> createEventDialog(
  BuildContext context,
  WidgetRef ref, {
  DateTime? initialDate,
  String? projectId,
}) async {
  final base = initialDate ?? DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    barrierDismissible: false,
  );
  if (date == null || !context.mounted) return;
  final title = await promptText(context, title: '新建日程', label: '日程标题');
  if (title == null || !context.mounted) return;
  final allDay = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SimpleDialog(
      title: const Text('日程类型'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, false),
          child: const ListTile(
            leading: Icon(Icons.schedule),
            title: Text('指定时间'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, true),
          child: const ListTile(
            leading: Icon(Icons.today),
            title: Text('全天日程'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const ListTile(
            leading: Icon(Icons.close),
            title: Text('取消'),
          ),
        ),
      ],
    ),
  );
  if (allDay == null || !context.mounted) return;

  DateTime start;
  DateTime end;
  if (allDay) {
    start = DateTime(date.year, date.month, date.day);
    end = start.add(const Duration(days: 1));
  } else {
    final startValue = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base.add(const Duration(hours: 1))),
      helpText: '开始时间',
      barrierDismissible: false,
    );
    if (startValue == null || !context.mounted) return;
    final endValue = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (startValue.hour + 1) % 24,
        minute: startValue.minute,
      ),
      helpText: '结束时间',
      barrierDismissible: false,
    );
    if (endValue == null) return;
    start = DateTime(
        date.year, date.month, date.day, startValue.hour, startValue.minute);
    end = DateTime(
        date.year, date.month, date.day, endValue.hour, endValue.minute);
    if (!end.isAfter(start)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('结束时间必须晚于开始时间')),
        );
      }
      return;
    }
  }

  if (!context.mounted) return;
  final repeat = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SimpleDialog(
      title: const Text('重复'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'NONE'),
          child: const Text('不重复'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'FREQ=DAILY;INTERVAL=1'),
          child: const Text('每天'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'FREQ=WEEKLY;INTERVAL=1'),
          child: const Text('每周'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (repeat == null) return;
  var departure = const _DepartureDraft();
  if (!allDay && context.mounted) {
    final preparation = TextEditingController(text: '0');
    final travel = TextEditingController(text: '0');
    var enabled = false;
    final value = await showDialog<_DepartureDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('出发提醒（可选）'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用出发提醒'),
                subtitle: const Text('按照准备时间和路程时间计算'),
                value: enabled,
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
              TextField(
                controller: preparation,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '准备时间（分钟）'),
              ),
              TextField(
                controller: travel,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '路程时间（分钟）'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消创建'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _DepartureDraft(
                  enabled: enabled,
                  preparationMinutes: int.tryParse(preparation.text) ?? 0,
                  travelMinutes: int.tryParse(travel.text) ?? 0,
                ),
              ),
              child: const Text('继续'),
            ),
          ],
        ),
      ),
    );
    preparation.dispose();
    travel.dispose();
    if (value == null) return;
    departure = value;
  }
  await EventRepository(ref.read(databaseProvider)).create(EventDraft(
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    localDate: allDay ? DateKeys.toLocalDateKey(start) : null,
    repeatRule: repeat == 'NONE' ? null : repeat,
    projectId: projectId,
    preparationMinutes: departure.preparationMinutes,
    travelMinutes: departure.travelMinutes,
    departureReminderEnabled: departure.enabled,
  ));
  ref.read(refreshProvider.notifier).state++;
  await refreshReminders(ref);
  if (context.mounted) _success(context, '日程已创建');
}

class _DepartureDraft {
  const _DepartureDraft({
    this.enabled = false,
    this.preparationMinutes = 0,
    this.travelMinutes = 0,
  });
  final bool enabled;
  final int preparationMinutes;
  final int travelMinutes;
}

void _success(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> showQuickCreateSheet(BuildContext context, WidgetRef ref) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('快速创建', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: '取消',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _CreateChoice(
                    value: 'task',
                    icon: Icons.check_circle_outline,
                    label: '任务'),
                _CreateChoice(
                    value: 'event', icon: Icons.event_outlined, label: '日程'),
                _CreateChoice(
                    value: 'project', icon: Icons.folder_outlined, label: '项目'),
                _CreateChoice(
                    value: 'list', icon: Icons.checklist, label: '清单'),
                _CreateChoice(value: 'habit', icon: Icons.repeat, label: '习惯'),
                _CreateChoice(
                    value: 'saved',
                    icon: Icons.bookmark_add_outlined,
                    label: '收藏'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  switch (selected) {
    case 'task':
      await createTaskDialog(context, ref);
      break;
    case 'event':
      await createEventDialog(context, ref);
      break;
    case 'project':
      await createProjectDialog(context, ref);
      break;
    case 'list':
      await createListDialog(context, ref);
      break;
    case 'habit':
      await createHabitDialog(context, ref);
      break;
    case 'saved':
      final value = await promptText(
        context,
        title: '快速收藏',
        label: '笔记或链接',
      );
      if (value == null) break;
      final isLink = Uri.tryParse(value)?.hasScheme == true;
      await SavedItemRepository(ref.read(databaseProvider)).create(
        SavedItemDraft(
          title: isLink ? Uri.parse(value).host : value,
          itemType: isLink ? SavedItemType.link : SavedItemType.note,
          content: value,
          sourceUri: isLink ? value : null,
        ),
      );
      ref.read(refreshProvider.notifier).state++;
      if (context.mounted) _success(context, '已保存到资料库');
      break;
  }
}

class _CreateChoice extends StatelessWidget {
  const _CreateChoice({
    required this.value,
    required this.icon,
    required this.label,
  });
  final String value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, value),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      );
}
