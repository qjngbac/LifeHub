import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/today/application/today_service.dart';
import 'package:lifehub/features/today/application/today_mode.dart';
import 'package:lifehub/features/today/application/today_preferences.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage>
    with WidgetsBindingObserver {
  Timer? _midnightTimer;
  late int _dateKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateKey = DateKeys.toLocalDateKey(DateTime.now());
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshForDateChange();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer =
        Timer(tomorrow.difference(now) + const Duration(seconds: 1), () {
      _refreshForDateChange();
      _scheduleMidnight();
    });
  }

  void _refreshForDateChange() {
    final key = DateKeys.toLocalDateKey(DateTime.now());
    if (key != _dateKey && mounted) {
      _dateKey = key;
      ref.read(refreshProvider.notifier).state++;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final settings = ref.watch(appSettingsProvider);
    final preferenceStore = ref.watch(sharedPreferencesProvider);
    final todayPreferences =
        preferenceStore == null ? null : TodayPreferences(preferenceStore);
    final moduleOrder =
        todayPreferences?.loadOrder() ?? TodayPreferences.defaultOrder;
    final collapsed = todayPreferences?.loadCollapsed() ?? const <String>{};
    final motto = todayPreferences?.loadMotto();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('今天'),
                Text(
                  DateFormat('M月d日 EEEE', 'zh_CN').format(now),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (motto != null) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _MottoTicker(
                  text: motto,
                  onTap: () => _editMotto(context, todayPreferences!),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (todayPreferences != null && motto == null)
            IconButton(
              tooltip: '添加首页标语',
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => _editMotto(context, todayPreferences),
            ),
          IconButton(
            tooltip: '自定义今天',
            icon: const Icon(Icons.tune),
            onPressed: todayPreferences == null
                ? null
                : () => _customizeToday(context, todayPreferences),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'today_add',
        onPressed: () => createTaskDialog(context, ref, dueOn: now),
        tooltip: '新建任务',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<TodaySnapshot>(
              future: TodayService(ref.read(databaseProvider)).load(now),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.error_outline,
                    text: '今天的数据暂时无法加载',
                    action: () => ref.read(refreshProvider.notifier).state++,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                final rankedTasks =
                    TodayModeRanking.tasks(data.tasks, settings.modes);
                final rankedEvents =
                    TodayModeRanking.events(data.events, settings.modes);
                if (data.tasks.isEmpty &&
                    data.events.isEmpty &&
                    data.habits.isEmpty &&
                    data.anniversaries.isEmpty &&
                    data.trips.isEmpty &&
                    data.goals.isEmpty &&
                    data.focus == null) {
                  return _Message(
                    icon: Icons.wb_sunny_outlined,
                    text: '今天还没有安排\n从一个简单任务开始吧',
                    action: () => createTaskDialog(context, ref, dueOn: now),
                    actionText: '添加任务',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.read(refreshProvider.notifier).state++,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      _SummaryCard(data: data),
                      _ModeHint(modes: settings.modes),
                      for (final moduleId in moduleOrder)
                        ..._moduleWidgets(
                          context,
                          moduleId,
                          data,
                          rankedTasks,
                          rankedEvents,
                          settings,
                          now,
                          todayPreferences,
                          collapsed.contains(moduleId),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMotto(
    BuildContext context,
    TodayPreferences preferences,
  ) async {
    final current = preferences.loadMotto();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MottoDialog(initialValue: current),
    );
    if (value == null) return;
    await preferences.saveMotto(value);
    if (mounted) setState(() {});
  }

  List<Widget> _moduleWidgets(
    BuildContext context,
    String id,
    TodaySnapshot data,
    List<TaskEntry> tasks,
    List<TodayEvent> events,
    AppSettings settings,
    DateTime now,
    TodayPreferences? preferences,
    bool collapsed,
  ) {
    final content = <Widget>[];
    var title = '';
    switch (id) {
      case 'focus':
        title = '当前专注与计时';
        final focus = data.focus;
        if (focus != null) {
          content.add(Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.timer_outlined)),
              title: Text(focus.mode == 'STOPWATCH'
                  ? (focus.status == 'PAUSED' ? '计时已暂停' : '正向计时中')
                  : (focus.status == 'PAUSED' ? '专注已暂停' : '专注进行中')),
              subtitle: Text(focus.mode == 'STOPWATCH'
                  ? '记录实际投入时长'
                  : '计划 ${focus.plannedMinutes} 分钟'),
              trailing: Text(focus.status == 'PAUSED' ? '暂停' : '进行中'),
            ),
          ));
        }
      case 'goals':
        title = '当前目标';
        content.addAll(data.goals.map((value) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.flag_outlined)),
                title: Text(value.goal.name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: value.progress),
                ),
                trailing: Text('${(value.progress * 100).round()}%'),
              ),
            )));
      case 'trips':
        title = '即将出发';
        content.addAll(data.trips.map((value) => Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE0E8),
                  child: Icon(Icons.luggage_outlined),
                ),
                title: Text(value.project.name),
                subtitle: Text(
                  '${DateFormat('M月d日').format(DateKeys.fromLocalDateKey(value.trip.startDate))} 出发',
                ),
                trailing: Text(
                  value.daysUntil == 0 ? '今天出发' : '还有 ${value.daysUntil} 天',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )));
      case 'anniversaries':
        title = '即将到来的日子';
        content.addAll(data.anniversaries.map((value) => Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEDBF),
                  child: Icon(Icons.celebration_outlined),
                ),
                title: Text(value.entry.title),
                subtitle: Text(value.entry.repeatYearly ? '每年重复' : '重要日期'),
                trailing: Text(
                  value.daysUntil == 0 ? '就是今天' : '还有 ${value.daysUntil} 天',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )));
      case 'events':
      case 'courses':
        final courses = id == 'courses';
        title = courses ? '今日课程' : '时间安排';
        content.addAll(events.where((event) => event.isCourse == courses).map(
              (event) => Card(
                color: TodayModeRanking.eventScore(event, settings.modes) > 0
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                child: ListTile(
                  leading: Icon(
                      courses ? Icons.school_outlined : Icons.event_outlined),
                  title: Text(event.title),
                  subtitle: Text(
                    '${DateFormat.Hm().format(event.start)}–${DateFormat.Hm().format(event.end)}${event.location == null ? '' : ' · ${event.location}'}',
                  ),
                ),
              ),
            ));
      case 'tasks':
        title = '待办任务';
        content.addAll(tasks.map((task) => Card(
              color: TodayModeRanking.taskScore(task, settings.modes) > 0
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              child: ListTile(
                title: Text(task.title),
                subtitle: Text(_taskTimeText(task)),
                onTap: () => editTaskDialog(context, ref, task),
                trailing: Checkbox(
                  value: task.status == TaskStatus.done,
                  onChanged: (checked) async {
                    await TaskRepository(ref.read(databaseProvider)).setStatus(
                      task.id,
                      checked == true ? TaskStatus.done : TaskStatus.todo,
                    );
                    ref.read(refreshProvider.notifier).state++;
                    await refreshReminders(ref);
                  },
                ),
              ),
            )));
      case 'habits':
        title = '今日习惯';
        content.addAll(data.habits.map((entry) => Card(
              child: CheckboxListTile(
                value: entry.completed,
                title: Text(entry.habit.name),
                subtitle:
                    Text('目标 ${entry.habit.targetCount}${entry.habit.unit}'),
                onChanged: (checked) async {
                  await HabitRepository(ref.read(databaseProvider)).checkIn(
                    entry.habit.id,
                    now,
                    value: checked == true ? entry.habit.targetCount : 0,
                  );
                  ref.read(refreshProvider.notifier).state++;
                  await refreshReminders(ref);
                },
              ),
            )));
    }
    if (content.isEmpty) return const [];
    return [
      _SectionTitle(
        title,
        collapsed: collapsed,
        onTap: preferences == null
            ? null
            : () async {
                await preferences.setCollapsed(id, !collapsed);
                if (mounted) setState(() {});
              },
      ),
      if (!collapsed) ...content,
    ];
  }

  Future<void> _customizeToday(
    BuildContext context,
    TodayPreferences preferences,
  ) async {
    final order = preferences.loadOrder();
    final collapsed = preferences.loadCollapsed();
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(children: [
              ListTile(
                title: const Text('自定义今天'),
                subtitle: const Text('拖动排序，开关控制默认展开'),
                trailing: IconButton(
                  tooltip: '完成',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await preferences.saveOrder(order);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: order.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setLocal(() {
                      final value = order.removeAt(oldIndex);
                      order.insert(newIndex, value);
                    });
                  },
                  itemBuilder: (context, index) {
                    final id = order[index];
                    return SwitchListTile(
                      key: ValueKey(id),
                      secondary: const Icon(Icons.drag_handle),
                      title: Text(_todayModuleLabel(id)),
                      value: !collapsed.contains(id),
                      onChanged: (value) async {
                        await preferences.setCollapsed(id, !value);
                        setLocal(() {
                          value ? collapsed.remove(id) : collapsed.add(id);
                        });
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _MottoDialog extends StatefulWidget {
  const _MottoDialog({required this.initialValue});

  final String? initialValue;

  @override
  State<_MottoDialog> createState() => _MottoDialogState();
}

class _MottoDialogState extends State<_MottoDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.initialValue == null ? '设置首页标语' : '编辑首页标语',
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '标语',
            hintText: '例如：今天也要稳稳向前',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('保存'),
          ),
        ],
      );
}

class _MottoTicker extends StatefulWidget {
  const _MottoTicker({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_MottoTicker> createState() => _MottoTickerState();
}

class _MottoTickerState extends State<_MottoTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration:
          Duration(seconds: (widget.text.runes.length / 3).ceil().clamp(8, 24)),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _MottoTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.duration =
          Duration(seconds: (widget.text.runes.length / 3).ceil().clamp(8, 24));
      _controller.forward(from: 0);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        );
    return InkWell(
      key: const Key('today_motto'),
      onTap: widget.onTap,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              maxLines: 1,
              textDirection: Directionality.of(context),
            )..layout();
            final distance = constraints.maxWidth + painter.width + 32;
            return ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    constraints.maxWidth + 16 - distance * _controller.value,
                    0,
                  ),
                  child: child,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.text, maxLines: 1, style: style),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _todayModuleLabel(String id) => switch (id) {
      'focus' => '专注',
      'goals' => '目标',
      'tasks' => '任务',
      'events' => '日程',
      'courses' => '课程',
      'habits' => '习惯',
      'anniversaries' => '纪念日',
      'trips' => '旅行',
      _ => id,
    };

String _taskTimeText(TaskEntry task) {
  if (task.dueAt == null) return '今天';
  final end =
      DateTime.fromMillisecondsSinceEpoch(task.dueAt!, isUtc: true).toLocal();
  if (task.startAt == null) return '今天截止 ${DateFormat.Hm().format(end)}';
  final start =
      DateTime.fromMillisecondsSinceEpoch(task.startAt!, isUtc: true).toLocal();
  return '${DateFormat.Hm().format(start)}–${DateFormat.Hm().format(end)}';
}

class _ModeHint extends StatelessWidget {
  const _ModeHint({required this.modes});
  final Set<LifeMode> modes;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      if (modes.contains(LifeMode.student)) '学生：课程与学习任务优先',
      if (modes.contains(LifeMode.work)) '工作：项目与会议优先',
      if (modes.contains(LifeMode.daily)) '日常：生活任务与习惯优先',
      if (modes.contains(LifeMode.outdoor)) '户外：行程与装备清单优先',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: messages
            .map((value) => Chip(
                  avatar: const Icon(Icons.tune, size: 18),
                  label: Text(value),
                ))
            .toList(),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});
  final TodaySnapshot data;
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Count(value: data.events.length, label: '安排'),
              _Count(value: data.tasks.length, label: '任务'),
              _Count(
                  value: data.habits.where((value) => value.completed).length,
                  label: '已打卡'),
            ],
          ),
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ]);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.collapsed = false, this.onTap});
  final String text;
  final bool collapsed;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
          child: Row(children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (onTap != null)
              Icon(collapsed ? Icons.expand_more : Icons.expand_less),
          ]),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon,
      required this.text,
      required this.action,
      this.actionText = '重试'});
  final IconData icon;
  final String text;
  final VoidCallback action;
  final String actionText;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: action, child: Text(actionText)),
          ]),
        ),
      );
}
