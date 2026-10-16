import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_actions.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/event/domain/departure_rules.dart';
import 'package:lifehub/features/event/presentation/event_form.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';
import 'package:lifehub/shared/ui/actionable_empty_state.dart';

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
    final unit = switch (range) {
      CalendarRange.day => '天',
      CalendarRange.week => '周',
      CalendarRange.month => '月',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          TextButton(
            onPressed: () => setState(() => selected = DateTime.now()),
            child: const Tooltip(message: '回到今天', child: Text('今天')),
          ),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SegmentedButton<CalendarRange>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一$unit',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftWindow(-1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        _rangeTitle(window.$1, window.$2, range),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一$unit',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftWindow(1),
                ),
              ],
            ),
          ),
          if (range == CalendarRange.month)
            _MonthStrip(
              selected: selected,
              onSelected: (date) => setState(() => selected = date),
            ),
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
                  return ActionableEmptyState(
                    icon: Icons.event_available_outlined,
                    title: '这个时间段还没有安排',
                    message: '添加日程，按日期安排需要参加的事情。',
                    actionLabel: '添加日程',
                    onAction: () =>
                        createEventDialog(context, ref, initialDate: selected),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final showDate =
                        range != CalendarRange.day &&
                        (index == 0 ||
                            !_sameDay(items[index - 1].start, item.start));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                            child: Text(
                              DateFormat('M月d日 E', 'zh_CN').format(item.start),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        _CalendarEventCard(
                          item: item,
                          onTap: item.event == null
                              ? null
                              : () => _showEventActions(item.event!),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _shiftWindow(int direction) {
    setState(() {
      if (range == CalendarRange.month) {
        final month = DateTime(selected.year, selected.month + direction);
        final lastDay = DateTime(month.year, month.month + 1, 0).day;
        selected = DateTime(
          month.year,
          month.month,
          selected.day > lastDay ? lastDay : selected.day,
        );
      } else {
        selected = DateTime(
          selected.year,
          selected.month,
          selected.day + direction * (range == CalendarRange.week ? 7 : 1),
        );
      }
    });
  }

  Future<List<_CalendarItem>> _load(DateTime start, DateTime end) async {
    final database = ref.read(databaseProvider);
    final events = await EventRepository(
      database,
    ).occurrencesWindow(start, end);
    final values = <_CalendarItem>[
      ...events.map(
        (value) => _CalendarItem(
          title: value.event.title,
          start: value.start,
          end: value.end,
          location: value.event.location,
          allDay: value.event.allDay,
          event: value.event,
          occurrenceStart: value.start,
        ),
      ),
    ];
    final split =
        values.expand((item) => _splitAcrossDays(item, start, end)).toList()
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              title: const Text('编辑日程'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('归档日程'),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除日程',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final repository = EventRepository(ref.read(databaseProvider));
    if (action == 'edit') {
      final draft = await showEventForm(context, current: event);
      if (draft == null || !mounted) return;
      await repository.update(event.id, draft);
    } else if (action == 'archive') {
      final confirmed =
          await showDialog<bool>(
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
      final confirmed =
          await showDialog<bool>(
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
    if (!mounted) return;
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
  const _CalendarItem({
    required this.title,
    required this.start,
    required this.end,
    this.location,
    this.course = false,
    this.allDay = false,
    this.event,
    this.occurrenceStart,
    this.overlap = false,
  });
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;
  final bool course;
  final bool allDay;
  final EventEntry? event;
  final DateTime? occurrenceStart;
  final bool overlap;

  _CalendarItem copyWithOverlap() => _CalendarItem(
    title: title,
    start: start,
    end: end,
    location: location,
    course: course,
    allDay: allDay,
    event: event,
    occurrenceStart: occurrenceStart,
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
  final lastDay = DateTime(
    lastInstant.year,
    lastInstant.month,
    lastInstant.day,
  );
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
        occurrenceStart: item.occurrenceStart,
      );
    }
    day = nextDay;
  }
}

class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({required this.item, this.onTap});
  final _CalendarItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final endTime =
        item.end.hour == 0 &&
            item.end.minute == 0 &&
            !_sameDay(item.start, item.end)
        ? '24:00'
        : DateFormat.Hm().format(item.end);
    final time = item.allDay
        ? '00:00–23:59'
        : '${DateFormat.Hm().format(item.start)}–$endTime';
    final departure = item.event?.departureReminderEnabled == true
        ? DepartureRules.suggestedDepartureAt(
            start: item.occurrenceStart ?? item.start,
            travelMinutes: item.event!.travelMinutes,
            preparationMinutes: item.event!.preparationMinutes,
          )
        : null;
    final departureLabel = departure == null
        ? null
        : '${_sameDay(departure, item.start) ? '' : '${DateFormat('M月d日').format(departure)} '}${DateFormat.Hm().format(departure)}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45), width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(item.course ? Icons.school_outlined : Icons.schedule_outlined,
                  size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(time, style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary, fontWeight: FontWeight.w500))),
                if (onTap != null)
                  Icon(Icons.chevron_right, size: 18, color: colors.outline),
              ]),
              const SizedBox(height: 5),
              Text(item.title, style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 16, fontWeight: FontWeight.w600)),
              if (item.location != null || item.course || item.event?.repeatRule != null || item.overlap) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 4, children: [
                  if (item.location != null)
                    Text(item.location!, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  if (item.course)
                    Text('课程', style: theme.textTheme.labelSmall?.copyWith(color: colors.outline)),
                  if (item.event?.repeatRule != null)
                    Text('重复', style: theme.textTheme.labelSmall?.copyWith(color: colors.outline)),
                  if (item.overlap)
                    Text('时间重叠', style: theme.textTheme.labelMedium?.copyWith(color: colors.error)),
                ]),
              ],
              if (departureLabel != null)
                Padding(padding: const EdgeInsets.only(top: 6),
                  child: Text('建议 $departureLabel 出发', style: theme.textTheme.bodySmall?.copyWith(color: colors.primary))),
            ],
          ),
        ),
      ),
    );
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
