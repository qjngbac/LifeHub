import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/emergency_card_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class MedicationPage extends ConsumerStatefulWidget {
  const MedicationPage({super.key});
  @override
  ConsumerState<MedicationPage> createState() => _MedicationPageState();
}

class _MedicationPageState extends ConsumerState<MedicationPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final database = ref.read(databaseProvider);
    final repository = MedicationRepository(database);
    return Scaffold(
      appBar: AppBar(title: const Text('用药提醒与急救卡'), actions: [
        IconButton(
          tooltip: '急救卡',
          icon: const Icon(Icons.contact_emergency_outlined),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const EmergencyCardPage())),
        )
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(repository),
          icon: const Icon(Icons.add_alert_outlined),
          label: const Text('提醒')),
      body: FutureBuilder<List<MedicationPlanEntry>>(
        key: ValueKey(revision),
        future: repository.plans(activeOnly: false),
        builder: (context, snapshot) {
          final values = snapshot.data;
          if (values == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    '这里使用 Android 系统本地通知：App 不停留在此页时也可提醒，重启 App 后会恢复未来计划。它不是系统闹钟，能否响铃取决于通知、精确提醒和电池权限。模块不诊断、不推荐药物，也不生成剂量。'),
              ),
            ),
            if (values.isEmpty)
              const Card(
                child: Padding(
                    padding: EdgeInsets.all(20), child: Text('还没有提醒计划')),
              ),
            for (final plan in values)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.medication_outlined),
                      title: Text(plan.name),
                      subtitle: Text([
                        if (plan.instructions != null) plan.instructions!,
                        repository.reminderTimes(plan).join('、'),
                        plan.active ? '系统通知已启用' : '已停用',
                      ].where((v) => v.isNotEmpty).join(' · ')),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) => _action(repository, plan, value),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(
                              value: 'toggle',
                              child: Text(plan.active ? '停用提醒' : '启用提醒')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ),
                        ],
                      ),
                    ),
                    if (plan.active)
                      Wrap(spacing: 8, children: [
                        for (final time in repository.reminderTimes(plan))
                          ActionChip(
                            label: Text('$time 打卡'),
                            onPressed: () async {
                              final parts = time.split(':');
                              await repository.checkIn(
                                plan.id,
                                DateTime.now(),
                                int.parse(parts[0]) * 60 + int.parse(parts[1]),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$time 已记录')));
                              }
                            },
                          )
                      ]),
                  ]),
                ),
              ),
          ]);
        },
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
      await repository.updatePlan(
          plan.id, _draftFrom(plan, active: !plan.active));
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
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除')),
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
        reminderTimes: MedicationRepository(ref.read(databaseProvider))
            .reminderTimes(plan),
        notes: plan.notes,
        active: active ?? plan.active,
      );

  Future<void> _edit(
    MedicationRepository repository, {
    MedicationPlanEntry? current,
  }) async {
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
    final draft = await showDialog<MedicationPlanDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title: Text(current == null ? '添加提醒计划' : '编辑提醒计划'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称 *')),
            TextField(
                controller: instructions,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '你的说明（可选）')),
            TextField(
                controller: times,
                decoration: const InputDecoration(
                    labelText: '提醒时间，逗号分隔', helperText: '例如 08:00,20:30')),
            _PlanDateTile(
                title: '开始日期',
                value: start,
                onChanged: (value) => setDialogState(() => start = value!)),
            _PlanDateTile(
                title: '结束日期（可选）',
                value: end,
                allowClear: true,
                onChanged: (value) => setDialogState(() => end = value)),
            TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注（可选）')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用系统通知'),
              value: active,
              onChanged: (value) => setDialogState(() => active = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  MedicationPlanDraft(
                    name: name.text,
                    instructions: instructions.text,
                    startDate: start,
                    endDate: end,
                    reminderTimes: times.text
                        .split(RegExp('[,，]'))
                        .map((v) => v.trim())
                        .where((v) => v.isNotEmpty)
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

class _PlanDateTile extends StatelessWidget {
  const _PlanDateTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
  });
  final String title;
  final DateTime? value;
  final bool allowClear;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(value == null
            ? '未设置'
            : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}'),
        trailing: allowClear && value != null
            ? IconButton(
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear),
              )
            : const Icon(Icons.event_outlined),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            barrierDismissible: false,
          );
          if (picked != null) onChanged(picked);
        },
      );
}
