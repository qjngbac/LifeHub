import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class HabitsPage extends ConsumerStatefulWidget {
  const HabitsPage({super.key});

  @override
  ConsumerState<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends ConsumerState<HabitsPage> {
  String _selectedPeriod = 'ALL'; // 'ALL', 'MORNING', 'AFTERNOON', 'EVENING'

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  String _classifyPeriod(HabitEntry habit) {
    if (habit.reminderPolicy != null && habit.reminderPolicy!.contains(':')) {
      final parts = habit.reminderPolicy!.split(':');
      final hour = int.tryParse(parts.first) ?? -1;
      if (hour >= 0 && hour < 12) return 'MORNING';
      if (hour >= 12 && hour < 18) return 'AFTERNOON';
      if (hour >= 18 && hour < 24) return 'EVENING';
    }
    final name = habit.name.toLowerCase();
    if (name.contains('早') || name.contains('晨') || name.contains('醒')) {
      return 'MORNING';
    }
    if (name.contains('午')) {
      return 'AFTERNOON';
    }
    if (name.contains('晚') ||
        name.contains('夜') ||
        name.contains('睡') ||
        name.contains('复盘')) {
      return 'EVENING';
    }
    return 'ALL';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = HabitRepository(ref.read(databaseProvider));
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('习惯'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habit_add',
        onPressed: () => _createAdvanced(context, ref, repository),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    showCheckmark: false,
                    label: const Text('全部'),
                    selected: _selectedPeriod == 'ALL',
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedPeriod = 'ALL');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: const Text('晨间'),
                    selected: _selectedPeriod == 'MORNING',
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedPeriod = 'MORNING');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.wb_twilight_outlined, size: 16),
                    label: const Text('午间'),
                    selected: _selectedPeriod == 'AFTERNOON',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedPeriod = 'AFTERNOON');
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: const Icon(Icons.nightlight_outlined, size: 16),
                    label: const Text('晚间'),
                    selected: _selectedPeriod == 'EVENING',
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedPeriod = 'EVENING');
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<(
              List<HabitEntry>,
              Map<String, Map<int, HabitLogEntry>>
            )>(
              future: _load(repository, today),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('习惯加载失败'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allHabits = snapshot.data!.$1;
                final allLogs = snapshot.data!.$2;

                final habits = allHabits.where((habit) {
                  if (_selectedPeriod == 'ALL') return true;
                  final period = _classifyPeriod(habit);
                  return period == _selectedPeriod;
                }).toList();

                if (habits.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.spa_outlined,
                            size: 56,
                            color:
                                Theme.of(context).colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedPeriod == 'ALL'
                                ? '还没有习惯，每天进步一点点'
                                : '当前时段无习惯',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final recentDays = List.generate(
                  7,
                  (i) => today.subtract(Duration(days: 6 - i)),
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  children: habits.map((habit) {
                    final habitLogs = allLogs[habit.id] ?? {};
                    final todayKey = DateKeys.toLocalDateKey(today);
                    final todayCompleted =
                        (habitLogs[todayKey]?.value ?? 0) >= habit.targetCount;
                    final period = _classifyPeriod(habit);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              habit.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (period != 'ALL') ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: period == 'MORNING'
                                                    ? Colors.amber.shade100
                                                    : period == 'AFTERNOON'
                                                        ? Colors.blue.shade100
                                                        : Colors
                                                            .purple.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                period == 'MORNING'
                                                    ? '晨间'
                                                    : period == 'AFTERNOON'
                                                        ? '午间'
                                                        : '晚间',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: period == 'MORNING'
                                                      ? Colors.amber.shade900
                                                      : period == 'AFTERNOON'
                                                          ? Colors.blue.shade900
                                                          : Colors
                                                              .purple.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      FutureBuilder<(int, double)>(
                                        future: _metrics(
                                            repository, habit.id, today),
                                        builder: (context, metrics) {
                                          final streak =
                                              metrics.data?.$1 ?? 0;
                                          final weekly =
                                              ((metrics.data?.$2 ?? 0) * 100)
                                                  .round();
                                          return Text(
                                            '${HabitRules.label(habit.scheduleRule)} · 连续 $streak 天 · 本周 $weekly%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: todayCompleted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (checked) async {
                                    HapticFeedback.lightImpact();
                                    await repository.checkIn(
                                      habit.id,
                                      today,
                                      value: checked == true
                                          ? habit.targetCount
                                          : 0,
                                    );
                                    ref.read(refreshProvider.notifier).state++;
                                    await refreshReminders(ref);
                                  },
                                ),
                                PopupMenuButton<String>(
                                  tooltip: '习惯操作',
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                        value: 'edit', child: Text('编辑')),
                                    PopupMenuItem(
                                        value: 'archive', child: Text('归档')),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      await _createAdvanced(
                                          context, ref, repository,
                                          current: habit);
                                    } else if (action == 'archive') {
                                      final confirmed = await showDialog<bool>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              title: const Text('归档习惯？'),
                                              content: Text(habit.name),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: const Text('取消')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text('归档')),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                      if (confirmed) {
                                        await repository.archive(habit.id);
                                      }
                                      ref.read(refreshProvider.notifier).state++;
                                      await refreshReminders(ref);
                                    } else {
                                      final confirmed = await showDialog<bool>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              title: const Text('删除习惯？'),
                                              content: const Text(
                                                  '删除后不会出现在搜索或归档中。'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: const Text('取消')),
                                                FilledButton(
                                                    style:
                                                        FilledButton.styleFrom(
                                                      backgroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .error,
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text('删除')),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                      if (confirmed) {
                                        await repository.delete(habit.id);
                                      }
                                      ref.read(refreshProvider.notifier).state++;
                                      await refreshReminders(ref);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            // 近 7 天打卡热力圆点矩阵与快速补卡
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: recentDays.map((day) {
                                final dateKey = DateKeys.toLocalDateKey(day);
                                final isDone = (habitLogs[dateKey]?.value ??
                                        0) >=
                                    habit.targetCount;
                                final isToday = day.year == today.year &&
                                    day.month == today.month &&
                                    day.day == today.day;
                                final label = isToday
                                    ? '今'
                                    : _weekdayLabels[day.weekday - 1];

                                return InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () async {
                                    HapticFeedback.lightImpact();
                                    await repository.checkIn(
                                      habit.id,
                                      day,
                                      value: isDone ? 0 : habit.targetCount,
                                    );
                                    ref.read(refreshProvider.notifier).state++;
                                    await refreshReminders(ref);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .hideCurrentSnackBar();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          duration:
                                              const Duration(seconds: 1),
                                          content: Text(
                                            '${habit.name} (${day.month}/${day.day}): ${isDone ? '已取消打卡' : '打卡成功'}',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Tooltip(
                                    message:
                                        '${day.month}月${day.day}日: ${isDone ? '已打卡' : '未打卡'} (点击补卡/取消)',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: isToday
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isToday
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            width: 26,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isDone
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Colors.transparent,
                                              border: Border.all(
                                                color: isDone
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : isToday
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : Colors.grey.shade300,
                                                width: isToday ? 2 : 1,
                                              ),
                                            ),
                                            child: isDone
                                                ? const Icon(
                                                    Icons.check,
                                                    size: 16,
                                                    color: Colors.white,
                                                  )
                                                : isToday
                                                    ? Icon(
                                                        Icons.add,
                                                        size: 14,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                      )
                                                    : null,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${day.day}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<(List<HabitEntry>, Map<String, Map<int, HabitLogEntry>>)> _load(
    HabitRepository repository,
    DateTime today,
  ) async {
    final habits = await repository.list();
    final logs = await repository.logsForDays(today, 7);
    return (habits, logs);
  }

  Future<(int, double)> _metrics(
    HabitRepository repository,
    String habitId,
    DateTime today,
  ) async =>
      (
        await repository.streak(habitId, today),
        await repository.weeklyProgress(habitId, today),
      );

  Future<void> _createAdvanced(
    BuildContext context,
    WidgetRef ref,
    HabitRepository repository, {
    HabitEntry? current,
  }) async {
    final name = TextEditingController(text: current?.name ?? '');
    final target = TextEditingController(text: '${current?.targetCount ?? 1}');
    final reminder = TextEditingController(text: current?.reminderPolicy ?? '');
    var rule = current?.scheduleRule ?? 'DAILY';

    final draft = await showDialog<HabitDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => KeyboardSafeFormDialog(
          title: Text(current == null ? '新建习惯' : '编辑习惯'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '习惯名称'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: rule,
                decoration: const InputDecoration(labelText: '频率'),
                items: const [
                  DropdownMenuItem(value: 'DAILY', child: Text('每天')),
                  DropdownMenuItem(value: 'WEEKDAYS', child: Text('工作日')),
                  DropdownMenuItem(value: 'WEEKLY_X:3', child: Text('每周 3 次')),
                  DropdownMenuItem(
                      value: 'WEEKDAY_SET:1,3,5', child: Text('每周一、三、五')),
                  DropdownMenuItem(
                      value: 'WEEKDAY_SET:6,7', child: Text('休息日（周六、周日）')),
                  DropdownMenuItem(
                      value: 'WEEKDAY_SET:2,4,6', child: Text('每周二、四、六')),
                ],
                onChanged: (value) => setState(() => rule = value ?? rule),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每次目标数量'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reminder,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: '提醒时间（可选）',
                  hintText: '例如 21:00',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('晨间 08:00'),
                    onPressed: () => setState(() => reminder.text = '08:00'),
                  ),
                  ActionChip(
                    label: const Text('午间 13:00'),
                    onPressed: () => setState(() => reminder.text = '13:00'),
                  ),
                  ActionChip(
                    label: const Text('晚间 21:00'),
                    onPressed: () => setState(() => reminder.text = '21:00'),
                  ),
                  if (reminder.text.isNotEmpty)
                    ActionChip(
                      label: const Text('清空'),
                      onPressed: () => setState(() => reminder.clear()),
                    ),
                ],
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
                final count = int.tryParse(target.text) ?? 0;
                if (name.text.trim().isNotEmpty && count > 0) {
                  Navigator.pop(
                    context,
                    HabitDraft(
                      name: name.text.trim(),
                      scheduleRule: rule,
                      targetCount: count,
                      reminderPolicy: reminder.text.trim().isEmpty
                          ? null
                          : reminder.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    target.dispose();
    reminder.dispose();

    if (draft != null) {
      if (current == null) {
        await repository.create(draft);
      } else {
        await repository.update(current.id, draft);
      }
      ref.read(refreshProvider.notifier).state++;
      await refreshReminders(ref);
    }
  }
}
