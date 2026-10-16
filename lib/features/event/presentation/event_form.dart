import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

Future<EventDraft?> showEventForm(
  BuildContext context, {
  DateTime? initialDate,
  String? projectId,
  EventEntry? current,
}) async {
  final base = initialDate ?? DateTime.now();
  final originalStart = current == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          current.startAt,
          isUtc: true,
        ).toLocal();
  final originalEnd = current == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          current.endAt,
          isUtc: true,
        ).toLocal();
  var allDay = current?.allDay ?? false;
  final durationDays = originalEnd == null
      ? 1
      : originalEnd.difference(originalStart!).inDays;
  var startDate = allDay && current?.localDate != null
      ? DateKeys.fromLocalDateKey(current!.localDate!)
      : DateTime(
          (originalStart ?? base).year,
          (originalStart ?? base).month,
          (originalStart ?? base).day,
        );
  var endDate = originalEnd == null
      ? startDate
      : allDay
      ? DateTime(
          startDate.year,
          startDate.month,
          startDate.day + (durationDays < 1 ? 1 : durationDays) - 1,
        )
      : DateTime(originalEnd.year, originalEnd.month, originalEnd.day);
  var startTime = originalStart == null
      ? const TimeOfDay(hour: 9, minute: 0)
      : TimeOfDay.fromDateTime(originalStart);
  var endTime = originalEnd == null
      ? const TimeOfDay(hour: 10, minute: 0)
      : TimeOfDay.fromDateTime(originalEnd);
  final initialStartDate = startDate;
  final initialEndDate = endDate;
  final initialStartTime = startTime;
  final initialEndTime = endTime;
  final title = TextEditingController(text: current?.title);
  final location = TextEditingController(text: current?.location);
  final notes = TextEditingController(text: current?.notes);
  final preparation = TextEditingController(
    text: '${current?.preparationMinutes ?? 0}',
  );
  final travel = TextEditingController(text: '${current?.travelMinutes ?? 0}');
  var departureEnabled = current?.departureReminderEnabled ?? false;
  var repeat = current?.repeatRule ?? 'NONE';
  const repeats = {
    'NONE': '不重复',
    'FREQ=DAILY;INTERVAL=1': '每天',
    'FREQ=WEEKLY;INTERVAL=1': '每周',
  };
  String? titleError;
  String? timeError;
  String? preparationError;
  String? travelError;

  final route = DialogRoute<EventDraft>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> pickDate(bool start) async {
          final selected = start ? startDate : endDate;
          final picked = await showDatePicker(
            context: context,
            initialDate: selected,
            firstDate: DateTime(selected.year < 2020 ? selected.year : 2020),
            lastDate: DateTime(
              selected.year > 2100 ? selected.year : 2100,
              12,
              31,
            ),
            barrierDismissible: false,
          );
          if (picked == null || !context.mounted) return;
          setDialogState(() {
            if (start) {
              final wasSameDay =
                  DateKeys.toLocalDateKey(startDate) ==
                  DateKeys.toLocalDateKey(endDate);
              startDate = picked;
              if (wasSameDay) endDate = picked;
            } else {
              endDate = picked;
            }
            timeError = null;
          });
        }

        Future<void> pickTime(bool start) async {
          final picked = await showTimePicker(
            context: context,
            initialTime: start ? startTime : endTime,
            helpText: start ? '开始时间' : '结束时间',
            barrierDismissible: false,
          );
          if (picked == null || !context.mounted) return;
          setDialogState(() {
            if (start) {
              startTime = picked;
            } else {
              endTime = picked;
            }
            timeError = null;
          });
        }

        return KeyboardSafeFormDialog(
          title: Text(current == null ? '新建日程' : '编辑日程'),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                textInputAction: TextInputAction.next,
                decoration: _decoration('日程标题').copyWith(errorText: titleError),
                onChanged: (_) {
                  if (titleError != null) {
                    setDialogState(() => titleError = null);
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('全天日程'),
                subtitle: const Text('当天 00:00–23:59'),
                value: allDay,
                onChanged: (value) => setDialogState(() {
                  allDay = value;
                  timeError = null;
                }),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    _EventDateTimeRow(
                      label: '开始',
                      date: startDate,
                      time: allDay
                          ? const TimeOfDay(hour: 0, minute: 0)
                          : startTime,
                      onDate: () => pickDate(true),
                      onTime: allDay ? null : () => pickTime(true),
                    ),
                    const SizedBox(height: 4),
                    _EventDateTimeRow(
                      label: '结束',
                      date: endDate,
                      time: allDay
                          ? const TimeOfDay(hour: 23, minute: 59)
                          : endTime,
                      onDate: () => pickDate(false),
                      onTime: allDay ? null : () => pickTime(false),
                    ),
                  ],
                ),
              ),
              if (timeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    timeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (!allDay &&
                  departureEnabled &&
                  (preparationError != null || travelError != null))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '出发提醒时间需填写非负整数',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                title: const Text('更多选项'),
                subtitle: const Text('重复、地点、备注与提醒', style: TextStyle(fontSize: 12)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 10, bottom: 8),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: repeat,
                    isExpanded: true,
                    decoration: _decoration('重复'),
                    items: [
                      for (final entry in repeats.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      if (!repeats.containsKey(repeat))
                        DropdownMenuItem(
                          value: repeat,
                          child: const Text('保留原有重复规则'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => repeat = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: location,
                    decoration: _decoration('地点'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 3,
                    decoration: _decoration('备注'),
                  ),
                  if (!allDay) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('出发提醒'),
                      subtitle: const Text('按准备时间和路程时间计算'),
                      value: departureEnabled,
                      onChanged: (value) =>
                          setDialogState(() => departureEnabled = value),
                    ),
                    if (departureEnabled) ...[
                      TextField(
                        controller: preparation,
                        keyboardType: TextInputType.number,
                        decoration: _decoration(
                          '准备时间（分钟）',
                        ).copyWith(errorText: preparationError),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: travel,
                        keyboardType: TextInputType.number,
                        decoration: _decoration(
                          '路程时间（分钟）',
                        ).copyWith(errorText: travelError),
                      ),
                    ],
                  ],
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
                var start = DateTime(
                  startDate.year,
                  startDate.month,
                  startDate.day,
                  allDay ? 0 : startTime.hour,
                  allDay ? 0 : startTime.minute,
                );
                var end = allDay
                    ? DateTime(endDate.year, endDate.month, endDate.day + 1)
                    : DateTime(
                        endDate.year,
                        endDate.month,
                        endDate.day,
                        endTime.hour,
                        endTime.minute,
                      );
                // 未改变日期和时间时，保留导入日程原有的秒数及全天时间戳。
                if (current != null && allDay == current.allDay) {
                  if (startDate == initialStartDate &&
                      startTime == initialStartTime) {
                    start = originalStart!;
                  }
                  if (endDate == initialEndDate && endTime == initialEndTime) {
                    end = originalEnd!;
                  }
                }
                final preparationMinutes = int.tryParse(
                  preparation.text.trim(),
                );
                final travelMinutes = int.tryParse(travel.text.trim());
                setDialogState(() {
                  titleError = title.text.trim().isEmpty ? '请输入日程标题' : null;
                  timeError = end.isAfter(start)
                      ? null
                      : allDay
                      ? '结束日期不能早于开始日期'
                      : '结束时间必须晚于开始时间';
                  preparationError =
                      !allDay &&
                          departureEnabled &&
                          (preparationMinutes == null || preparationMinutes < 0)
                      ? '请输入非负整数'
                      : null;
                  travelError =
                      !allDay &&
                          departureEnabled &&
                          (travelMinutes == null || travelMinutes < 0)
                      ? '请输入非负整数'
                      : null;
                });
                if (titleError != null ||
                    timeError != null ||
                    preparationError != null ||
                    travelError != null) {
                  return;
                }
                Navigator.pop(
                  context,
                  EventDraft(
                    title: title.text.trim(),
                    start: start,
                    end: end,
                    allDay: allDay,
                    localDate: allDay
                        ? DateKeys.toLocalDateKey(startDate)
                        : null,
                    eventType: current?.eventType ?? 'LIFE',
                    projectId: current?.projectId ?? projectId,
                    repeatRule: repeat == 'NONE' ? null : repeat,
                    location: location.text,
                    notes: notes.text,
                    preparationMinutes:
                        preparationMinutes != null && preparationMinutes >= 0
                        ? preparationMinutes
                        : 0,
                    travelMinutes: travelMinutes != null && travelMinutes >= 0
                        ? travelMinutes
                        : 0,
                    departureReminderEnabled: !allDay && departureEnabled,
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
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  for (final controller in [title, location, notes, preparation, travel]) {
    controller.dispose();
  }
  return result;
}

InputDecoration _decoration(String label) => InputDecoration(
  labelText: label,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
);

class _EventDateTimeRow extends StatelessWidget {
  const _EventDateTimeRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onDate,
    required this.onTime,
  });
  final String label;
  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onDate;
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: '选择$label日期',
              child: InkWell(
                onTap: onDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('yyyy-MM-dd').format(date),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Tooltip(
              message: onTime == null ? '当天时间范围' : '选择$label时间',
              child: InkWell(
                onTap: onTime,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color:
                              onTime == null ? colors.outline : colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: onTime == null
                                ? colors.outline
                                : colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


