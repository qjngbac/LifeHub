import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/automation/application/automation_engine.dart';
import 'package:lifehub/features/automation/data/automation_repository.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = AutomationRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地自动化'),
        actions: [
          IconButton(
            tooltip: '执行历史',
            onPressed: () => _showHistory(context, repository),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '立即检查规则',
            onPressed: () async {
              await AutomationEngine(ref.read(databaseProvider))
                  .runDue(DateTime.now());
              ref.read(refreshProvider.notifier).state++;
            },
            icon: const Icon(Icons.play_arrow),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, repository),
        icon: const Icon(Icons.add),
        label: const Text('新建规则'),
      ),
      body: FutureBuilder(
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = snapshot.data!;
          if (rules.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('还没有自动化规则'),
                  SizedBox(height: 8),
                  Text('这里只支持可预览、可关闭的本地规则，不执行任意脚本。'),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return Card(
                child: InkWell(
                  onTap: () => _preview(context, rule),
                  child: SwitchListTile(
                    value: rule.enabled,
                    title: Text(rule.name),
                    subtitle: Text(
                      '${_triggerLabel(rule.triggerType, rule.triggerJson)} → ${_actionLabel(rule.actionType, rule.actionJson)}',
                    ),
                    onChanged: (value) async {
                      await repository.setEnabled(rule.id, value);
                      ref.read(refreshProvider.notifier).state++;
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    AutomationRepository repository,
  ) async {
    final template = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('选择规则模板'),
              subtitle: Text('创建前可以确认触发条件和结果'),
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat),
              title: const Text('每周创建任务'),
              subtitle: const Text('适合周复盘、每周整理等固定任务'),
              onTap: () => Navigator.pop(context, 'WEEKLY'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('课程结束后复习'),
              subtitle: const Text('在指定星期和时间后创建复习任务'),
              onTap: () => Navigator.pop(context, 'COURSE'),
            ),
            ListTile(
              leading: const Icon(Icons.celebration_outlined),
              title: const Text('纪念日前准备'),
              subtitle: const Text('提前若干天创建准备任务'),
              onTap: () => Navigator.pop(context, 'ANNIVERSARY'),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('未完成任务顺延'),
              subtitle: const Text('每天把逾期未完成任务移动到当天'),
              onTap: () => Navigator.pop(context, 'ROLLOVER'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || template == null) return;
    switch (template) {
      case 'WEEKLY':
        await _createWeekly(context, ref, repository);
      case 'COURSE':
        await _createCourse(context, ref, repository);
      case 'ANNIVERSARY':
        await _createAnniversary(context, ref, repository);
      case 'ROLLOVER':
        await _createRollover(context, ref, repository);
    }
  }

  Future<void> _createWeekly(
    BuildContext context,
    WidgetRef ref,
    AutomationRepository repository,
  ) async {
    final name = TextEditingController(text: '每周复盘');
    final title = TextEditingController(text: '完成本周复盘');
    var weekday = DateTime.sunday;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('创建每周任务规则'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '规则名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: '任务标题'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: '每周'),
                    items: List.generate(
                      7,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('周${'一二三四五六日'[index]}'),
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => weekday = value ?? weekday),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('创建')),
              ],
            ),
          ),
        ) ??
        false;
    if (confirmed &&
        name.text.trim().isNotEmpty &&
        title.text.trim().isNotEmpty) {
      await repository.create(AutomationRuleDraft(
        name: name.text,
        triggerType: 'WEEKLY',
        triggerJson: jsonEncode({'weekday': weekday}),
        actionType: 'CREATE_TASK',
        actionJson: jsonEncode({'title': title.text.trim()}),
      ));
      ref.read(refreshProvider.notifier).state++;
    }
    name.dispose();
    title.dispose();
  }

  Future<void> _createCourse(
    BuildContext context,
    WidgetRef ref,
    AutomationRepository repository,
  ) async {
    final name = TextEditingController(text: '课程结束后复习');
    final title = TextEditingController(text: '复习今天的课程');
    var weekday = DateTime.monday;
    var time = const TimeOfDay(hour: 18, minute: 0);
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('课程复习规则'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '规则名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: '任务标题'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: '课程所在星期'),
                    items: _weekdays,
                    onChanged: (value) =>
                        setState(() => weekday = value ?? weekday),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('课程结束时间'),
                    subtitle: Text(time.format(context)),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (picked != null) setState(() => time = picked);
                    },
                  ),
                  Text(
                      '预览：每周${_weekday(weekday)} ${time.format(context)} 后创建“${title.text}”'),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('创建'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (confirmed &&
        name.text.trim().isNotEmpty &&
        title.text.trim().isNotEmpty) {
      await repository.create(AutomationRuleDraft(
        name: name.text,
        triggerType: 'COURSE_REVIEW',
        triggerJson: jsonEncode({
          'weekday': weekday,
          'afterMinutes': time.hour * 60 + time.minute,
        }),
        actionType: 'CREATE_TASK',
        actionJson: jsonEncode({'title': title.text.trim()}),
      ));
      ref.read(refreshProvider.notifier).state++;
    }
    name.dispose();
    title.dispose();
  }

  Future<void> _createAnniversary(
    BuildContext context,
    WidgetRef ref,
    AutomationRepository repository,
  ) async {
    final values =
        await AnniversaryRepository(ref.read(databaseProvider)).listAll();
    if (!context.mounted) return;
    if (values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在生活记录中添加纪念日')),
      );
      return;
    }
    var selected = values.first.id;
    var days = 3;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('纪念日前准备'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: '纪念日'),
                  items: values
                      .map((value) => DropdownMenuItem(
                            value: value.id,
                            child: Text(value.title),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => selected = value ?? selected),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: days,
                  decoration: const InputDecoration(labelText: '提前'),
                  items: const [1, 3, 7, 14]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value 天'),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => days = value ?? days),
                ),
                const SizedBox(height: 12),
                const Text('预览：到期时创建“准备＋纪念日名称”任务。'),
              ]),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('创建'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (confirmed) {
      await repository.create(AutomationRuleDraft(
        name: '纪念日前准备',
        triggerType: 'ANNIVERSARY_BEFORE',
        triggerJson:
            jsonEncode({'anniversaryId': selected, 'daysBefore': days}),
        actionType: 'CREATE_TASK',
        actionJson: jsonEncode({'title': '准备{anniversary}'}),
      ));
      ref.read(refreshProvider.notifier).state++;
    }
  }

  Future<void> _createRollover(
    BuildContext context,
    WidgetRef ref,
    AutomationRepository repository,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('未完成任务顺延'),
            content:
                const Text('每天首次打开应用时，把截止日期早于今天且仍未完成的任务移动到今天 23:59。已完成任务不会改变。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('创建'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await repository.create(const AutomationRuleDraft(
      name: '未完成任务顺延',
      triggerType: 'DAILY',
      triggerJson: '{}',
      actionType: 'ROLLOVER_TASKS',
      actionJson: '{}',
    ));
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _showHistory(
    BuildContext context,
    AutomationRepository repository,
  ) async {
    final rules = await repository.list();
    final runs = await repository.runs();
    if (!context.mounted) return;
    final names = {for (final rule in rules) rule.id: rule.name};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: runs.isEmpty
            ? const SizedBox(height: 180, child: Center(child: Text('还没有执行记录')))
            : ListView(
                children: [
                  const ListTile(title: Text('执行历史')),
                  for (final run in runs)
                    ListTile(
                      leading: Icon(
                        run.status == 'SUCCESS'
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                      ),
                      title: Text(names[run.ruleId] ?? '已删除规则'),
                      subtitle: Text(
                          '${run.status} · ${DateTime.fromMillisecondsSinceEpoch(run.executedAt, isUtc: true).toLocal()}'),
                    ),
                ],
              ),
      ),
    );
  }

  void _preview(BuildContext context, dynamic rule) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(rule.name as String),
        content: Text(
            '${_triggerLabel(rule.triggerType as String, rule.triggerJson as String)}\n→ ${_actionLabel(rule.actionType as String, rule.actionJson as String)}\n\n同一规则在同一天最多成功执行一次，可随时关闭。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  static List<DropdownMenuItem<int>> get _weekdays => List.generate(
        7,
        (index) => DropdownMenuItem(
            value: index + 1, child: Text('周${'一二三四五六日'[index]}')),
      );
}

String _triggerLabel(String type, String source) {
  final value = jsonDecode(source);
  final trigger = value is Map ? value : const {};
  switch (type) {
    case 'WEEKLY':
      return '每周${_weekday(trigger['weekday'] as int?)}';
    case 'DAILY':
      return '每天首次检查';
    case 'COURSE_REVIEW':
      final minutes = trigger['afterMinutes'] as int? ?? 0;
      return '每周${_weekday(trigger['weekday'] as int?)} ${_clock(minutes)} 后';
    case 'ANNIVERSARY_BEFORE':
      return '纪念日前 ${trigger['daysBefore'] ?? '?'} 天';
    default:
      return type;
  }
}

String _actionLabel(String type, String source) {
  if (type == 'ROLLOVER_TASKS') return '顺延逾期未完成任务';
  if (type != 'CREATE_TASK') return type;
  final value = jsonDecode(source);
  return value is Map ? '创建任务“${value['title']}”' : '创建任务';
}

String _weekday(int? value) =>
    value != null && value >= 1 && value <= 7 ? '一二三四五六日'[value - 1] : '?';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
