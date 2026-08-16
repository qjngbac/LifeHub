import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/event/domain/departure_rules.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

enum CalendarRange { day, week, month }

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime selected = DateTime.now();
  CalendarRange range = CalendarRange.day;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final window = _window(selected, range);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          IconButton(
            tooltip: '选择日期',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _pickDate,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendar_add',
        onPressed: () => createEventDialog(context, ref, initialDate: selected),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<CalendarRange>(
              segments: const [
                ButtonSegment(value: CalendarRange.day, label: Text('日')),
                ButtonSegment(value: CalendarRange.week, label: Text('周')),
                ButtonSegment(value: CalendarRange.month, label: Text('月')),
              ],
              selected: {range},
              onSelectionChanged: (value) =>
                  setState(() => range = value.single),
            ),
          ),
          ListTile(
            title: Text(_rangeTitle(window.$1, window.$2, range),
                style: Theme.of(context).textTheme.titleLarge),
            onTap: _pickDate,
            trailing: TextButton(
                onPressed: () => setState(() => selected = DateTime.now()),
                child: const Text('回到今天')),
          ),
          if (range == CalendarRange.month)
            _MonthStrip(
                selected: selected,
                onSelected: (date) => setState(() => selected = date)),
          Expanded(
            child: FutureBuilder<List<_CalendarItem>>(
              future: _load(window.$1, window.$2),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('日程加载失败，请稍后重试'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.event_available_outlined, size: 56),
                      const SizedBox(height: 12),
                      const Text('这个时间段还没有安排'),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                          onPressed: () => createEventDialog(context, ref,
                              initialDate: selected),
                          child: const Text('添加日程')),
                    ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final showDate = index == 0 ||
                        !_sameDay(items[index - 1].start, item.start);
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                              child: Text(
                                  DateFormat('M月d日 E', 'zh_CN')
                                      .format(item.start),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                          Card(
                            child: ListTile(
                              leading: Icon(item.course
                                  ? Icons.school_outlined
                                  : Icons.event_outlined),
                              title: Text(item.title),
                              subtitle: Text([
                                item.allDay
                                    ? '全天'
                                    : '${DateFormat.Hm().format(item.start)}—${DateFormat.Hm().format(item.end)}',
                                if (item.location != null) item.location!,
                                if (item.event?.departureReminderEnabled ==
                                    true)
                                  '建议 ${DateFormat.Hm().format(DepartureRules.suggestedDepartureAt(start: item.start, travelMinutes: item.event!.travelMinutes, preparationMinutes: item.event!.preparationMinutes))} 出发',
                                if (item.overlap) '与其他日程重叠',
                              ].join(' · ')),
                              trailing: item.course
                                  ? const Chip(label: Text('课程'))
                                  : null,
                              onTap: item.event == null
                                  ? null
                                  : () => _showEventActions(item.event!),
                            ),
                          ),
                        ]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_CalendarItem>> _load(DateTime start, DateTime end) async {
    final database = ref.read(databaseProvider);
    final events =
        await EventRepository(database).occurrencesWindow(start, end);
    final values = <_CalendarItem>[
      ...events.map((value) => _CalendarItem(
            title: value.event.title,
            start: value.start,
            end: value.end,
            location: value.event.location,
            allDay: value.event.allDay,
            event: value.event,
          )),
    ];
    final split = values
        .expand((item) => _splitAcrossDays(item, start, end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < split.length; i++) {
      if (split[i].allDay) continue;
      for (var j = i + 1; j < split.length; j++) {
        if (!_sameDay(split[i].start, split[j].start)) break;
        if (!split[j].allDay &&
            split[i].start.isBefore(split[j].end) &&
            split[j].start.isBefore(split[i].end)) {
          split[i] = split[i].copyWithOverlap();
          split[j] = split[j].copyWithOverlap();
        }
      }
    }
    return split;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      barrierDismissible: false,
    );
    if (date != null && mounted) setState(() => selected = date);
  }

  Future<void> _showEventActions(EventEntry event) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(event.title),
            trailing: IconButton(
              tooltip: '取消',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑标题'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('归档日程'),
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text('删除日程',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final repository = EventRepository(ref.read(databaseProvider));
    if (action == 'edit') {
      final title = await promptText(
        context,
        title: '编辑日程',
        label: '日程标题',
        initial: event.title,
      );
      if (title == null) return;
      await repository.update(
        event.id,
        EventDraft(
          title: title,
          start: DateTime.fromMillisecondsSinceEpoch(event.startAt, isUtc: true)
              .toLocal(),
          end: DateTime.fromMillisecondsSinceEpoch(event.endAt, isUtc: true)
              .toLocal(),
          eventType: event.eventType,
          allDay: event.allDay,
          localDate: event.localDate,
          location: event.location,
          notes: event.notes,
          repeatRule: event.repeatRule,
          projectId: event.projectId,
          preparationMinutes: event.preparationMinutes,
          travelMinutes: event.travelMinutes,
          departureReminderEnabled: event.departureReminderEnabled,
        ),
      );
    } else if (action == 'archive') {
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('归档日程？'),
              content: Text(event.title),
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
      await repository.archive(event.id);
    } else {
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('删除日程？'),
              content: const Text('删除后不会出现在搜索或归档中。'),
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
      await repository.delete(event.id);
    }
    ref.read(refreshProvider.notifier).state++;
    await refreshReminders(ref);
  }
}

(DateTime, DateTime) _window(DateTime date, CalendarRange range) {
  final day = DateTime(date.year, date.month, date.day);
  return switch (range) {
    CalendarRange.day => (day, day.add(const Duration(days: 1))),
    CalendarRange.week => (
        day.subtract(Duration(days: day.weekday - 1)),
        day
            .subtract(Duration(days: day.weekday - 1))
            .add(const Duration(days: 7)),
      ),
    CalendarRange.month => (
        DateTime(day.year, day.month),
        DateTime(day.year, day.month + 1)
      ),
  };
}

String _rangeTitle(DateTime start, DateTime end, CalendarRange range) =>
    switch (range) {
      CalendarRange.day => DateFormat('yyyy年M月d日', 'zh_CN').format(start),
      CalendarRange.week =>
        '${DateFormat('M月d日').format(start)} – ${DateFormat('M月d日').format(end.subtract(const Duration(days: 1)))}',
      CalendarRange.month => DateFormat('yyyy年M月', 'zh_CN').format(start),
    };

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _CalendarItem {
  const _CalendarItem(
      {required this.title,
      required this.start,
      required this.end,
      this.location,
      this.course = false,
      this.allDay = false,
      this.event,
      this.overlap = false});
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final bool course;
  final bool allDay;
  final EventEntry? event;
  final bool overlap;

  _CalendarItem copyWithOverlap() => _CalendarItem(
        title: title,
        start: start,
        end: end,
        location: location,
        course: course,
        allDay: allDay,
        event: event,
        overlap: true,
      );
}

Iterable<_CalendarItem> _splitAcrossDays(
  _CalendarItem item,
  DateTime windowStart,
  DateTime windowEnd,
) sync* {
  var day = DateTime(item.start.year, item.start.month, item.start.day);
  final lastInstant = item.end.subtract(const Duration(microseconds: 1));
  final lastDay =
      DateTime(lastInstant.year, lastInstant.month, lastInstant.day);
  while (!day.isAfter(lastDay)) {
    final nextDay = day.add(const Duration(days: 1));
    final segmentStart = item.start.isAfter(day) ? item.start : day;
    final segmentEnd = item.end.isBefore(nextDay) ? item.end : nextDay;
    if (segmentEnd.isAfter(windowStart) && segmentStart.isBefore(windowEnd)) {
      yield _CalendarItem(
        title: item.title,
        start: segmentStart.isBefore(windowStart) ? windowStart : segmentStart,
        end: segmentEnd.isAfter(windowEnd) ? windowEnd : segmentEnd,
        location: item.location,
        course: item.course,
        allDay: item.allDay,
        event: item.event,
      );
    }
    day = nextDay;
  }
}

class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.selected, required this.onSelected});
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  @override
  Widget build(BuildContext context) {
    final days = DateTime(selected.year, selected.month + 1, 0).day;
    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: days,
        itemBuilder: (context, index) {
          final date = DateTime(selected.year, selected.month, index + 1);
          final active = date.day == selected.day;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChoiceChip(
                label: Text('${date.day}'),
                selected: active,
                onSelected: (_) => onSelected(date)),
          );
        },
      ),
    );
  }
}
