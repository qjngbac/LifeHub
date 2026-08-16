import 'package:flutter/material.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/cycle_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<MoodDraft?> showMoodRecordDialog(
  BuildContext context, {
  required DateTime date,
  String? relationshipId,
  MoodLogEntry? current,
}) async {
  var code = current?.moodCode ?? MoodCatalog.happy;
  var intensity = current?.intensity ?? 3;
  final note = TextEditingController(text: current?.note ?? '');
  final result = await showDialog<MoodDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('${date.month}月${date.day}日的心情'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: MoodCatalog.values.map((option) {
                final selected = code == option.code;
                return ChoiceChip(
                  selected: selected,
                  avatar: Text(option.emoji),
                  label: Text(option.label),
                  selectedColor: option.color.withValues(alpha: .36),
                  onSelected: (_) => setState(() => code = option.code),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Row(children: [
              const Text('感受强度'),
              Expanded(
                child: Slider(
                  value: intensity.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$intensity',
                  onChanged: (value) =>
                      setState(() => intensity = value.round()),
                ),
              ),
              Text('$intensity'),
            ]),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '想说的话（可选）',
                hintText: '只保存在本机，不进入全局搜索',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              MoodDraft(
                date: date,
                moodCode: code,
                intensity: intensity,
                note: note.text,
                relationshipId: relationshipId,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
  return result;
}

Future<LifeEventDraft?> showLifeEventDialog(
  BuildContext context, {
  required DateTime date,
  String? relationshipId,
  LifeEventEntry? current,
}) async {
  final title = TextEditingController(text: current?.title ?? '');
  final note = TextEditingController(text: current?.note ?? '');
  TimeOfDay? time = current?.timeMinutes == null
      ? null
      : TimeOfDay(
          hour: current!.timeMinutes! ~/ 60,
          minute: current.timeMinutes! % 60,
        );
  final result = await showDialog<LifeEventDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(current == null ? '添加当天事件' : '修改当天事件'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: title,
              autofocus: true,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '发生了什么'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(time == null ? '不设置具体时间' : time!.format(context)),
              trailing: time == null
                  ? null
                  : IconButton(
                      tooltip: '清除时间',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => time = null),
                    ),
              onTap: () async {
                final value = await showTimePicker(
                  context: context,
                  initialTime: time ?? TimeOfDay.now(),
                  barrierDismissible: false,
                );
                if (value != null) setState(() => time = value);
              },
            ),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '补充记录（可选）'),
            ),
            if (current != null) ...[
              const SizedBox(height: 12),
              AttachmentPanel(
                entityType: 'LIFE_EVENT',
                entityId: current.id,
                sensitive: relationshipId != null,
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('保存事件后，再次打开即可添加附件。'),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                LifeEventDraft(
                  title: title.text,
                  date: date,
                  timeMinutes:
                      time == null ? null : time!.hour * 60 + time!.minute,
                  note: note.text,
                  relationshipId: relationshipId,
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
  note.dispose();
  return result;
}

Future<RelationshipDraft?> showRelationshipDialog(
  BuildContext context, {
  RelationshipProfileEntry? current,
}) async {
  final name = TextEditingController(text: current?.name ?? '');
  final nickname = TextEditingController(text: current?.nickname ?? '');
  var start = current?.startDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.startDate!);
  var birthday = current?.birthday == null
      ? null
      : DateKeys.fromLocalDateKey(current!.birthday!);
  final result = await showDialog<RelationshipDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '建立关系档案' : '修改关系档案'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '对方名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nickname,
            decoration: const InputDecoration(labelText: '昵称（可选）'),
          ),
          _DateField(
            label: '在一起的日期（可选）',
            date: start,
            onChanged: (value) => setState(() => start = value),
          ),
          _DateField(
            label: '生日（可选）',
            date: birthday,
            onChanged: (value) => setState(() => birthday = value),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                RelationshipDraft(
                  name: name.text,
                  nickname: nickname.text,
                  startDate: start,
                  birthday: birthday,
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
  nickname.dispose();
  return result;
}

Future<CycleDraft?> showCycleDialog(
  BuildContext context, {
  required String relationshipId,
  required DateTime selectedDate,
}) async {
  var start = selectedDate;
  DateTime? end;
  final note = TextEditingController();
  final result = await showDialog<CycleDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('手动记录生理期'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('仅记录实际日期，不做医疗判断或周期预测。'),
          _DateField(
            label: '开始日期',
            date: start,
            allowClear: false,
            onChanged: (value) {
              if (value != null) setState(() => start = value);
            },
          ),
          _DateField(
            label: '结束日期（可稍后补充）',
            date: end,
            firstDate: start,
            onChanged: (value) => setState(() => end = value),
          ),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CycleDraft(
                relationshipId: relationshipId,
                start: start,
                end: end,
                note: note.text,
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
  return result;
}

Future<AnniversaryDraft?> showAnniversaryDialog(
  BuildContext context, {
  AnniversaryEntry? current,
  String? relationshipId,
  DateTime? initialDate,
}) async {
  final title = TextEditingController(text: current?.title ?? '');
  var date = current == null
      ? (initialDate ?? DateTime.now())
      : DateKeys.fromLocalDateKey(current.date);
  var repeat = current?.repeatYearly ?? true;
  var showInToday = current?.showInToday ?? true;
  final result = await showDialog<AnniversaryDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '添加纪念日' : '修改纪念日'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          _DateField(
            label: '日期',
            date: date,
            allowClear: false,
            onChanged: (value) {
              if (value != null) setState(() => date = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('每年重复'),
            value: repeat,
            onChanged: (value) => setState(() => repeat = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示在今天'),
            value: showInToday,
            onChanged: (value) => setState(() => showInToday = value),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                AnniversaryDraft(
                  title: title.text,
                  date: date,
                  repeatYearly: repeat,
                  relationshipId: relationshipId ?? current?.relationshipId,
                  category:
                      relationshipId != null || current?.relationshipId != null
                          ? 'RELATIONSHIP'
                          : 'LIFE',
                  showInToday: showInToday,
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
  return result;
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onChanged,
    this.firstDate,
    this.allowClear = true,
  });

  final String label;
  final DateTime? date;
  final DateTime? firstDate;
  final bool allowClear;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: Text(label),
        subtitle: Text(date == null
            ? '未设置'
            : '${date!.year}-${date!.month.toString().padLeft(2, '0')}-'
                '${date!.day.toString().padLeft(2, '0')}'),
        trailing: date != null && allowClear
            ? IconButton(
                tooltip: '清除日期',
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(null),
              )
            : null,
        onTap: () async {
          final min = firstDate ?? DateTime(1900);
          var initial = date ?? DateTime.now();
          if (initial.isBefore(min)) initial = min;
          final value = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: min,
            lastDate: DateTime(2200),
            barrierDismissible: false,
          );
          if (value != null) onChanged(value);
        },
      );
}
