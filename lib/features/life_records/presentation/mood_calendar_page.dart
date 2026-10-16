import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/life_records/presentation/life_month_calendar.dart';
import 'package:lifehub/features/life_records/presentation/life_record_dialogs.dart';

class MoodCalendarPage extends ConsumerStatefulWidget {
  const MoodCalendarPage({super.key});

  @override
  ConsumerState<MoodCalendarPage> createState() => _MoodCalendarPageState();
}

class _MoodCalendarPageState extends ConsumerState<MoodCalendarPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final database = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('心情日历'),
        actions: [
          IconButton(
            tooltip: '回到今天',
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                month = DateTime(now.year, now.month);
                selectedDate = DateTime(now.year, now.month, now.day);
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _chooseAdd(database),
        icon: const Icon(Icons.add),
        label: const Text('记录'),
      ),
      body: FutureBuilder<_MoodCalendarData>(
        key: ValueKey('${month.year}-${month.month}-$revision'),
        future: _load(database),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final selectedKey = DateKeys.toLocalDateKey(selectedDate);
          final mood = data.moods[selectedKey];
          final events = data.events
              .where((value) => value.localDate == selectedKey)
              .toList();
          final anniversaries = data.anniversaries
              .where((value) => _occursOn(value, selectedDate))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _MonthHeader(
                month: month,
                previous: () => _setMonth(-1),
                next: () => _setMonth(1),
                choose: _chooseMonth,
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -120) {
                    _setMonth(1);
                  } else if (velocity > 120) {
                    _setMonth(-1);
                  }
                },
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: LifeMonthCalendar(
                      month: month,
                      selectedDate: selectedDate,
                      onSelected: (value) => setState(() {
                        selectedDate = value;
                        if (value.month != month.month ||
                            value.year != month.year) {
                          month = DateTime(value.year, value.month);
                        }
                      }),
                      moodEmojis: {
                        for (final entry in data.moods.entries)
                          entry.key: MoodCatalog.emoji(entry.value.moodCode),
                      },
                      moodColors: {
                        for (final entry in data.moods.entries)
                          entry.key: MoodCatalog.color(entry.value.moodCode),
                      },
                      eventDates:
                          data.events.map((value) => value.localDate).toSet(),
                      anniversaryDates: data.anniversaryDateKeys,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                elevation: 0,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.insights,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _monthSummaryText(data.moods),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${selectedDate.month}月${selectedDate.day}日',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (mood == null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              selectedKey == DateKeys.toLocalDateKey(DateTime.now())
                                  ? '今日心情极速速记'
                                  : '当天心情极速速记',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            TextButton(
                              onPressed: () => _recordMood(database, mood),
                              child: const Text('详细记录'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final option in [
                              MoodCatalog.option(MoodCatalog.happy),
                              MoodCatalog.option(MoodCatalog.calm),
                              MoodCatalog.option(MoodCatalog.tired),
                              MoodCatalog.option(MoodCatalog.low),
                              MoodCatalog.option(MoodCatalog.irritated),
                            ])
                              InkWell(
                                key: ValueKey('quick-mood-${option.code}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  try {
                                    await MoodRepository(database).save(
                                      MoodDraft(
                                        date: selectedDate,
                                        moodCode: option.code,
                                        intensity: 3,
                                      ),
                                    );
                                    _refresh();
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '已记录为 ${option.emoji} ${option.label}，点击可修改'),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('记录失败：$e')),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  child: Column(
                                    children: [
                                      Text(option.emoji,
                                          style: const TextStyle(fontSize: 28)),
                                      const SizedBox(height: 4),
                                      Text(option.label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  child: ListTile(
                    leading: Text(
                      MoodCatalog.emoji(mood.moodCode),
                      style: const TextStyle(fontSize: 30),
                    ),
                    title: Text(
                        '${MoodCatalog.label(mood.moodCode)} · 强度 ${mood.intensity}/5'),
                    subtitle: mood.note == null ? null : Text(mood.note!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _recordMood(database, mood),
                  ),
                ),
              ],
              if (events.isNotEmpty) ...[
                const _SectionTitle(title: '当天事件'),
                ...events.map((value) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFDCE9FF),
                          child: Icon(Icons.auto_stories_outlined),
                        ),
                        title: Text(value.title),
                        subtitle: Text(_eventSubtitle(value)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) =>
                              _eventAction(database, value, action),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('修改')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                        onTap: () => _editEvent(database, value),
                      ),
                    )),
              ],
              if (anniversaries.isNotEmpty) ...[
                const _SectionTitle(title: '纪念日'),
                ...anniversaries.map((value) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFFFE9B9),
                          child: Icon(Icons.celebration_outlined),
                        ),
                        title: Text(value.title),
                        subtitle: Text(value.repeatYearly ? '每年重复' : '仅此一次'),
                      ),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  String _monthSummaryText(Map<int, MoodLogEntry> moods) {
    // 仅统计属于当月的心情，避免跨月网格溢出数据影响当月统计
    final currentMonthMoods = moods.values.where((m) {
      final date = DateKeys.fromLocalDateKey(m.localDate);
      return date.year == month.year && date.month == month.month;
    }).toList();
    if (currentMonthMoods.isEmpty) return '本月还没有记录心情';
    final count = currentMonthMoods.length;
    final freq = <String, int>{};
    for (final m in currentMonthMoods) {
      freq[m.moodCode] = (freq[m.moodCode] ?? 0) + 1;
    }
    var topCode = currentMonthMoods.first.moodCode;
    var maxCount = 0;
    freq.forEach((code, c) {
      if (c > maxCount) {
        maxCount = c;
        topCode = code;
      }
    });
    return '本月已记录 $count 天 · 最常感受：${MoodCatalog.emoji(topCode)} ${MoodCatalog.label(topCode)} ($maxCount次)';
  }

  Future<_MoodCalendarData> _load(AppDatabase database) async {
    final first = DateTime(month.year, month.month);
    // 覆盖 42 格日历网格的完整起止时间，让跨月溢出的非本月日期也能完整显示心情与事件
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = gridStart.add(const Duration(days: 41));
    final moods = await MoodRepository(database).listRange(gridStart, gridEnd);
    final events = await LifeEventRepository(database).listRange(gridStart, gridEnd);
    final anniversaries = await AnniversaryRepository(database).list();
    return _MoodCalendarData(
      moods: {for (final value in moods) value.localDate: value},
      events: events,
      anniversaries: anniversaries,
      anniversaryDateKeys: {
        for (final value in anniversaries)
          if (_monthDateKey(value, month) case final int key) key,
      },
    );
  }

  Future<void> _chooseAdd(AppDatabase database) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('记录 ${selectedDate.month}月${selectedDate.day}日'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const CircleAvatar(child: Text('😊')),
            title: const Text('心情'),
            subtitle: const Text('每天记录一个主要心情'),
            onTap: () => Navigator.pop(context, 'mood'),
          ),
          ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.auto_stories_outlined)),
            title: const Text('当天事件'),
            subtitle: const Text('记录已经发生的生活片段'),
            onTap: () => Navigator.pop(context, 'event'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'mood') {
      await _recordMood(
          database, await MoodRepository(database).forDate(selectedDate));
    } else {
      await _editEvent(database, null);
    }
  }

  Future<void> _recordMood(AppDatabase database, MoodLogEntry? current) async {
    final draft = await showMoodRecordDialog(
      context,
      date: selectedDate,
      current: current,
    );
    if (draft == null) return;
    await MoodRepository(database).save(draft);
    _refresh();
  }

  Future<void> _editEvent(
    AppDatabase database,
    LifeEventEntry? current,
  ) async {
    final draft = await showLifeEventDialog(
      context,
      date: selectedDate,
      current: current,
    );
    if (draft == null) return;
    final repository = LifeEventRepository(database);
    if (current == null) {
      await repository.create(draft);
    } else {
      await repository.update(current.id, draft);
    }
    _refresh();
  }

  Future<void> _eventAction(
    AppDatabase database,
    LifeEventEntry value,
    String action,
  ) async {
    if (action == 'edit') return _editEvent(database, value);
    final confirmed = await _confirmDelete('删除“${value.title}”？');
    if (!confirmed) return;
    await LifeEventRepository(database).delete(value.id);
    _refresh();
  }

  Future<bool> _confirmDelete(String title) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;

  void _setMonth(int offset) => setState(() {
        month = DateTime(month.year, month.month + offset);
        selectedDate = DateTime(month.year, month.month, 1);
      });

  Future<void> _chooseMonth() async {
    final value = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      barrierDismissible: false,
    );
    if (value != null) {
      setState(() {
        selectedDate = value;
        month = DateTime(value.year, value.month);
      });
    }
  }

  void _refresh() => setState(() => revision++);
}

class _MoodCalendarData {
  const _MoodCalendarData({
    required this.moods,
    required this.events,
    required this.anniversaries,
    required this.anniversaryDateKeys,
  });

  final Map<int, MoodLogEntry> moods;
  final List<LifeEventEntry> events;
  final List<AnniversaryEntry> anniversaries;
  final Set<int> anniversaryDateKeys;
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.previous,
    required this.next,
    required this.choose,
  });

  final DateTime month;
  final VoidCallback previous;
  final VoidCallback next;
  final VoidCallback choose;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton(onPressed: previous, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: TextButton(
            onPressed: choose,
            child: Text(
              '${month.year}年${month.month}月',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        IconButton(onPressed: next, icon: const Icon(Icons.chevron_right)),
      ]);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

String _eventSubtitle(LifeEventEntry value) {
  final parts = <String>[];
  if (value.timeMinutes != null) {
    parts.add(
      '${(value.timeMinutes! ~/ 60).toString().padLeft(2, '0')}:'
      '${(value.timeMinutes! % 60).toString().padLeft(2, '0')}',
    );
  }
  if (value.note != null) parts.add(value.note!);
  return parts.isEmpty ? '当天记录' : parts.join(' · ');
}

bool _occursOn(AnniversaryEntry value, DateTime date) {
  final source = DateKeys.fromLocalDateKey(value.date);
  if (!value.repeatYearly) {
    return DateKeys.toLocalDateKey(date) == value.date;
  }
  final day = source.day.clamp(1, DateTime(date.year, source.month + 1, 0).day);
  return source.month == date.month && day == date.day;
}

int? _monthDateKey(AnniversaryEntry value, DateTime month) {
  final source = DateKeys.fromLocalDateKey(value.date);
  if (!value.repeatYearly &&
      (source.year != month.year || source.month != month.month)) {
    return null;
  }
  if (source.month != month.month) return null;
  final day = source.day.clamp(1, DateTime(month.year, month.month + 1, 0).day);
  return DateKeys.toLocalDateKey(DateTime(month.year, month.month, day));
}
