import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/emergency_card_page.dart';
import 'package:lifehub/features/medication/presentation/medication_form_style.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class MedicationPage extends ConsumerStatefulWidget {
  const MedicationPage({super.key});
  @override
  ConsumerState<MedicationPage> createState() => _MedicationPageState();
}

/// 计划 + 今天打卡记录的聚合结果。
typedef _PlansView = ({List<MedicationPlanEntry> plans, Map<String, Set<int>> logs});

class _MedicationPageState extends ConsumerState<MedicationPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final database = ref.read(databaseProvider);
    final repository = MedicationRepository(database);
    final today = DateTime.now();
    final todayKey = DateKeys.toLocalDateKey(today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('用药提醒与急救卡'),
        actions: [
          IconButton(
            tooltip: '急救卡',
            icon: const Icon(Icons.contact_emergency_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EmergencyCardPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repository),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('提醒'),
      ),
      body: FutureBuilder<_PlansView>(
        key: ValueKey(revision),
        future: _load(repository, today),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('用药计划加载失败，请稍后重试'));
          }
          final view = snapshot.data;
          if (view == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              const _NoticeCard(),
              if (view.plans.isEmpty)
                const _EmptyPlans()
              else
                for (final plan in view.plans)
                  _buildPlanCard(
                    repository,
                    plan,
                    today,
                    todayKey,
                    view.logs[plan.id] ?? const <int>{},
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<_PlansView> _load(MedicationRepository repository, DateTime today) async {
    final plans = await repository.plans(activeOnly: false);
    final logs = await repository.checkedInMinutesByPlan(today);
    return (plans: plans, logs: logs);
  }

  Widget _buildPlanCard(
    MedicationRepository repository,
    MedicationPlanEntry plan,
    DateTime today,
    int todayKey,
    Set<int> checkedMinutes,
  ) {
    final theme = Theme.of(context);
    final times = repository.reminderTimes(plan);
    final activeToday = repository.isActiveOn(plan, today);

    // 状态徽章代替原来塞在副标题里的一长串文字
    final (String statusText, int statusTone) = !plan.active
        ? ('已停用', 2)
        : todayKey < plan.startDate
            ? ('尚未开始', 0)
            : (plan.endDate != null && todayKey > plan.endDate!)
                ? ('已结束', 2)
                : ('进行中', 0);

    final schedule = plan.endDate == null
        ? '从 ${_shortDate(plan.startDate)} 起'
        : '${_shortDate(plan.startDate)} ~ ${_shortDate(plan.endDate!)}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.medication_outlined,
                  color: plan.active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plan.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: plan.active
                                    ? null
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          MedicationStatusBadge(
                            text: statusText,
                            tone: statusTone,
                          ),
                        ],
                      ),
                      if ((plan.instructions ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          plan.instructions!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // 今天生效的计划，时间点由下方可点的打卡按钮承担，
                          // 这里不再重复列一遍时间
                          if (!activeToday)
                            for (final time in times)
                              MedicationMiniTag(
                                text: time,
                                icon: checkedMinutes.contains(
                                        parseReminderTime(time) ?? -1)
                                    ? Icons.check_circle
                                    : Icons.schedule,
                              ),
                          MedicationMiniTag(
                            text: schedule,
                            icon: Icons.date_range_outlined,
                          ),
                          if (activeToday && times.isNotEmpty)
                            MedicationMiniTag(
                              text:
                                  '今日 ${checkedMinutes.length}/${times.length}',
                              icon: Icons.task_alt,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _action(repository, plan, value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(plan.active ? '停用提醒' : '启用提醒'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除',
                        style:
                            TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (activeToday && times.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final time in times)
                    _CheckInChip(
                      time: time,
                      done: checkedMinutes.contains(
                          parseReminderTime(time) ?? -1),
                      onPressed: () async {
                        final minutes = parseReminderTime(time);
                        if (minutes == null) return;
                        await repository.checkIn(plan.id, DateTime.now(), minutes);
                        if (!mounted || !context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$time 已记录')),
                        );
                        setState(() => revision++);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _action(
    MedicationRepository repository,
    MedicationPlanEntry plan,
    String value,
  ) async {
    if (value == 'edit') {
      await _edit(repository, current: plan);
      return;
    }
    if (value == 'toggle') {
      await repository.updatePlan(plan.id, _draftFrom(plan, active: !plan.active));
    } else {
      final yes = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('删除这个用药提醒？'),
              content: const Text('数据和已安排的未来系统通知都会取消。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          ) ??
          false;
      if (!yes) return;
      await repository.deletePlan(plan.id);
    }
    await _rebuildNotifications();
    if (mounted) setState(() => revision++);
  }

  MedicationPlanDraft _draftFrom(MedicationPlanEntry plan, {bool? active}) =>
      MedicationPlanDraft(
        name: plan.name,
        instructions: plan.instructions,
        startDate: DateKeys.fromLocalDateKey(plan.startDate),
        endDate: plan.endDate == null
            ? null
            : DateKeys.fromLocalDateKey(plan.endDate!),
        reminderTimes:
            MedicationRepository(ref.read(databaseProvider)).reminderTimes(plan),
        notes: plan.notes,
        active: active ?? plan.active,
      );

  Future<void> _edit(
    MedicationRepository repository, {
    MedicationPlanEntry? current,
  }) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: current?.name);
    final instructions = TextEditingController(text: current?.instructions);
    final times = TextEditingController(
      text: current == null
          ? '08:00'
          : repository.reminderTimes(current).join(','),
    );
    final notes = TextEditingController(text: current?.notes);
    DateTime start = current == null
        ? DateTime.now()
        : DateKeys.fromLocalDateKey(current.startDate);
    DateTime? end = current?.endDate == null
        ? null
        : DateKeys.fromLocalDateKey(current!.endDate!);
    bool active = current?.active ?? true;
    var rangeError = '';

    final draft = await showDialog<MedicationPlanDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title: Text(current == null ? '添加提醒计划' : '编辑提醒计划'),
          body: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: medicationFieldDecoration(context, label: '名称'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? '请输入名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: instructions,
                  // 默认一行；填了换行或长文本会自动长高
                  minLines: 1,
                  maxLines: null,
                  decoration: medicationFieldDecoration(
                    context,
                    label: '你的说明',
                    hint: '选填，例如"饭后半小时"',
                  ),
                ),
                const MedicationSectionLabel('提醒时间'),
                TextFormField(
                  controller: times,
                  decoration: medicationFieldDecoration(
                    context,
                    label: '时间，用逗号分隔',
                    hint: '例如 08:00,20:30',
                    suffixIcon: IconButton(
                      tooltip: '用时间选择器添加一个时间',
                      icon: const Icon(Icons.schedule_outlined),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: const TimeOfDay(hour: 8, minute: 0),
                        );
                        if (picked == null) return;
                        final value = formatMinutes(
                            picked.hour * 60 + picked.minute);
                        final existing = times.text
                            .split(RegExp('[,，]'))
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList();
                        if (existing.contains(value)) return;
                        final next = [...existing, value]..sort();
                        setDialogState(() => times.text = next.join(','));
                      },
                    ),
                  ),
                  // 时间格式错误以前会直接抛 ArgumentError 崩在保存上，
                  // 现在改成表单内提示
                  validator: (_) {
                    final raw = times.text
                        .split(RegExp('[,，]'))
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty);
                    if (raw.isEmpty) return '至少填写一个提醒时间';
                    for (final item in raw) {
                      if (parseReminderTime(item) == null) {
                        return '「$item」格式不对，应为 08:00 这样的 HH:mm';
                      }
                    }
                    return null;
                  },
                ),
                const MedicationSectionLabel('生效时间'),
                Row(
                  children: [
                    Expanded(
                      child: MedicationDateField(
                        label: '开始日期',
                        value: start,
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            start = value;
                            rangeError = '';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MedicationDateField(
                        label: '结束日期',
                        value: end,
                        allowClear: true,
                        onChanged: (value) => setDialogState(() {
                          end = value;
                          rangeError = '';
                        }),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '不填结束日期表示长期服用',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                if (rangeError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      rangeError,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const MedicationSectionLabel('备注'),
                TextFormField(
                  controller: notes,
                  minLines: 1,
                  maxLines: null,
                  decoration: medicationFieldDecoration(
                    context,
                    label: '备注',
                    hint: '选填',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用系统通知'),
                  subtitle: const Text('关闭后计划仍会保留，只是不再提醒'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                if (end != null && end!.isBefore(start)) {
                  setDialogState(() => rangeError = '结束日期不能早于开始日期');
                  return;
                }
                Navigator.pop(
                  context,
                  MedicationPlanDraft(
                    name: name.text,
                    instructions: instructions.text,
                    startDate: start,
                    endDate: end,
                    reminderTimes: times.text
                        .split(RegExp('[,，]'))
                        .map((value) => value.trim())
                        .where((value) => value.isNotEmpty)
                        .toList(),
                    notes: notes.text,
                    active: active,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    instructions.dispose();
    times.dispose();
    notes.dispose();
    if (draft == null) return;
    if (current == null) {
      await repository.createPlan(draft);
    } else {
      await repository.updatePlan(current.id, draft);
    }
    await _rebuildNotifications();
    if (mounted) setState(() => revision++);
  }

  Future<void> _rebuildNotifications() =>
      NotificationService.instance.rebuildFuture(ref.read(databaseProvider));
}

String _shortDate(int key) {
  final value = DateKeys.fromLocalDateKey(key);
  return '${value.month}月${value.day}日';
}

/// 打卡按钮：未打卡是主色行动片，已打卡变成打勾的完成态。
class _CheckInChip extends StatelessWidget {
  const _CheckInChip({
    required this.time,
    required this.done,
    required this.onPressed,
  });
  final String time;
  final bool done;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return ActionChip(
        avatar: const Icon(Icons.check_circle, size: 16),
        label: Text('$time 已打卡'),
        onPressed: onPressed,
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.schedule_outlined, size: 16),
      label: Text('$time 打卡'),
      onPressed: onPressed,
    );
  }
}

/// 顶部说明：原来是整块粉色长段落，视觉上像报错；改成中性色的可展开提示。
class _NoticeCard extends StatefulWidget {
  const _NoticeCard();

  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard> {
  static const _text =
      '这里使用 Android 系统本地通知：App 不停留在此页时也可提醒，重启 App 后会恢复未来计划。'
      '它不是系统闹钟，能否响铃取决于通知、精确提醒和电池权限。'
      '模块不诊断、不推荐药物，也不生成剂量。';

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _text,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.alarm_add_outlined,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 14),
            Text('还没有提醒计划', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '例如「消炎药 08:00、20:30」，\n到点会用系统通知提醒你。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
