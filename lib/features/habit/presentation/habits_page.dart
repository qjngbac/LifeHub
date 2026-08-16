import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/features/habit/data/habit_repository.dart';
import 'package:lifehub/features/habit/domain/habit_rules.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class HabitsPage extends ConsumerWidget {
  const HabitsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = HabitRepository(ref.read(databaseProvider));
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('习惯')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habit_add',
        onPressed: () => _createAdvanced(context, ref, repository),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<(List<HabitEntry>, Map<String, HabitLogEntry>)>(
        future: _load(repository, today),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('习惯加载失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final habits = snapshot.data!.$1;
          final logs = snapshot.data!.$2;
          if (habits.isEmpty) return const Center(child: Text('还没有习惯，每天进步一点点'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: habits.map((habit) {
              final completed =
                  (logs[habit.id]?.value ?? 0) >= habit.targetCount;
              return Card(
                child: CheckboxListTile(
                  value: completed,
                  title: Text(habit.name),
                  subtitle: FutureBuilder<(int, double)>(
                    future: _metrics(repository, habit.id, today),
                    builder: (context, metrics) {
                      final streak = metrics.data?.$1 ?? 0;
                      final weekly = ((metrics.data?.$2 ?? 0) * 100).round();
                      return Text(
                        '${HabitRules.label(habit.scheduleRule)} · 连续 $streak 天 · 本周 $weekly%',
                      );
                    },
                  ),
                  secondary: PopupMenuButton<String>(
                    tooltip: '习惯操作',
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'archive', child: Text('归档')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await _createAdvanced(context, ref, repository,
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
                                          Navigator.pop(context, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('归档')),
                                ],
                              ),
                            ) ??
                            false;
                        if (confirmed) await repository.archive(habit.id);
                        ref.read(refreshProvider.notifier).state++;
                        await refreshReminders(ref);
                      } else {
                        final confirmed = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                title: const Text('删除习惯？'),
                                content: const Text('删除后不会出现在搜索或归档中。'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error),
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('删除')),
                                ],
                              ),
                            ) ??
                            false;
                        if (confirmed) await repository.delete(habit.id);
                        ref.read(refreshProvider.notifier).state++;
                        await refreshReminders(ref);
                      }
                    },
                  ),
                  onChanged: (checked) async {
                    await repository.checkIn(habit.id, today,
                        value: checked == true ? habit.targetCount : 0);
                    ref.read(refreshProvider.notifier).state++;
                    await refreshReminders(ref);
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<(List<HabitEntry>, Map<String, HabitLogEntry>)> _load(
    HabitRepository repository,
    DateTime today,
  ) async =>
      (await repository.list(), await repository.logsForDate(today));

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
      BuildContext context, WidgetRef ref, HabitRepository repository,
      {HabitEntry? current}) async {
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
          body: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
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
                      ));
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
