import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/data/cycle_repository.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';
import 'package:lifehub/features/life_records/presentation/life_month_calendar.dart';
import 'package:lifehub/features/life_records/presentation/life_record_dialogs.dart';

class RelationshipSpacePage extends ConsumerStatefulWidget {
  const RelationshipSpacePage({super.key});

  @override
  ConsumerState<RelationshipSpacePage> createState() =>
      _RelationshipSpacePageState();
}

class _RelationshipSpacePageState extends ConsumerState<RelationshipSpacePage> {
  String? selectedRelationshipId;
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
        title: const Text('关系空间'),
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
          IconButton(
            tooltip: '添加关系档案',
            onPressed: () => _editProfile(database, null),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      floatingActionButton: selectedRelationshipId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _chooseAdd(database),
              icon: const Icon(Icons.add),
              label: const Text('记录'),
            ),
      body: FutureBuilder<_RelationshipPageData>(
        key: ValueKey(
          '$selectedRelationshipId-${month.year}-${month.month}-$revision',
        ),
        future: _load(database),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.profiles.isEmpty) return _empty(database);
          final profile = data.profile!;
          final selectedKey = DateKeys.toLocalDateKey(selectedDate);
          final mood = data.moods[selectedKey];
          final events = data.events
              .where((value) => value.localDate == selectedKey)
              .toList();
          final cycles = data.cycles
              .where((value) =>
                  CycleRepository(database).containsDate(value, selectedDate))
              .toList();
          final anniversaries = data.anniversaries
              .where((value) => _occursOn(value, selectedDate))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFDDE9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFF80AB).withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(Icons.favorite, color: Color(0xFFE91E63), size: 22),
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
                                        profile.name,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (profile.nickname?.isNotEmpty == true) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          profile.nickname!,
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (profile.startDate != null) ...[
                                  const SizedBox(height: 6),
                                  _companionshipWidget(context, profile.startDate!),
                                ],
                              ],
                            ),
                          ),
                          if (data.profiles.length > 1)
                            PopupMenuButton<String>(
                              tooltip: '切换档案',
                              icon: const Icon(Icons.swap_horiz_rounded),
                              onSelected: (id) => setState(() {
                                selectedRelationshipId = id;
                                revision++;
                              }),
                              itemBuilder: (_) => [
                                for (final p in data.profiles)
                                  PopupMenuItem(
                                    value: p.id,
                                    child: Row(
                                      children: [
                                        if (p.id == profile.id)
                                          const Icon(Icons.check, size: 16, color: Colors.pink)
                                        else
                                          const SizedBox(width: 16),
                                        const SizedBox(width: 8),
                                        Text(p.nickname?.isNotEmpty == true
                                            ? '${p.name} (${p.nickname})'
                                            : p.name),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _editProfile(database, profile);
                              } else {
                                _archiveProfile(database, profile);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('修改档案')),
                              PopupMenuItem(value: 'archive', child: Text('归档档案')),
                            ],
                          ),
                        ],
                      ),
                      if (_cycleCareBanner(context, database, data.cycles) != null) ...[
                        const SizedBox(height: 10),
                        _cycleCareBanner(context, database, data.cycles)!,
                      ],
                    ],
                  ),
                ),
              ),
              Row(children: [
                IconButton(
                  onPressed: () => _setMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _chooseDate,
                    child: Text(
                      '${month.year}年${month.month}月',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _setMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
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
                        if (value.year != month.year ||
                            value.month != month.month) {
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
                      cycleDates: data.cycleDateKeys,
                      anniversaryDates: data.anniversaryDateKeys,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Row(
                  children: [
                    const Icon(Icons.event_note_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${selectedDate.month}月${selectedDate.day}日 · 共同记录',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            mood == null ? '😶' : MoodCatalog.emoji(mood.moodCode),
                            style: const TextStyle(fontSize: 28),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mood == null
                                      ? '对方心情（暂未记录）'
                                      : '${MoodCatalog.label(mood.moodCode)} · 强度 ${mood.intensity}/5',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                if (mood?.note?.isNotEmpty == true) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    mood!.note!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () => _recordMood(database, profile.id, mood),
                            icon: Icon(mood == null ? Icons.edit_note : Icons.edit, size: 16),
                            label: Text(mood == null ? '写备注' : '修改'),
                          ),
                        ],
                      ),
                      if (mood == null) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final opt in [
                              MoodCatalog.values.firstWhere((o) => o.code == MoodCatalog.happy),
                              MoodCatalog.values.firstWhere((o) => o.code == MoodCatalog.calm),
                              MoodCatalog.values.firstWhere((o) => o.code == MoodCatalog.hopeful),
                              MoodCatalog.values.firstWhere((o) => o.code == MoodCatalog.tired),
                              MoodCatalog.values.firstWhere((o) => o.code == MoodCatalog.sad),
                            ])
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _quickSaveMood(database, profile.id, opt.code),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Column(
                                    children: [
                                      Text(opt.emoji, style: const TextStyle(fontSize: 22)),
                                      const SizedBox(height: 2),
                                      Text(opt.label, style: const TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (cycles.isNotEmpty)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: const Color(0xFFFF80AB).withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  color: const Color(0xFFFFF0F5),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFD8E6),
                      child: Icon(Icons.water_drop_outlined, color: Color(0xFFE91E63)),
                    ),
                    title: const Text(
                      '生理期记录',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('当天在手动记录的生理周期范围内'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (_) => _deleteCycle(database, cycles.first),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                ),
              ...events.map((value) => Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCE9FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_stories_outlined, color: Color(0xFF1976D2), size: 20),
                      ),
                      title: Text(
                        value.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(value.note ?? '共同事件'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editEvent(database, profile.id, value);
                          } else {
                            _deleteEvent(database, value);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('修改')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                      onTap: () => _editEvent(database, profile.id, value),
                    ),
                  )),
              ...anniversaries.map((value) => Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: const Color(0xFFFFB300).withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    color: const Color(0xFFFFFDF5),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDBF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.celebration_outlined, color: Color(0xFFF57F17), size: 20),
                      ),
                      title: Text(
                        value.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(value.repeatYearly ? '每年重复纪念' : '重要日期记录'),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(AppDatabase database) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.favorite_outline, size: 64),
            const SizedBox(height: 16),
            Text(
              '先建立一个关系档案，再记录每天的心情与共同事件',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _editProfile(database, null),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('建立关系档案'),
            ),
          ]),
        ),
      );

  Future<_RelationshipPageData> _load(AppDatabase database) async {
    final profiles = await RelationshipRepository(database).list();
    if (profiles.isEmpty) return const _RelationshipPageData(profiles: []);
    var profile = profiles.first;
    if (selectedRelationshipId != null) {
      profile = profiles
              .where((value) => value.id == selectedRelationshipId)
              .firstOrNull ??
          profiles.first;
    }
    selectedRelationshipId = profile.id;
    final first = DateTime(month.year, month.month);
    // 覆盖 42 格日历网格的完整起止时间，让跨月溢出的前后月日期也能完整显示心情与事件
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final gridEnd = gridStart.add(const Duration(days: 41));
    final moods = await MoodRepository(database)
        .listRange(gridStart, gridEnd, relationshipId: profile.id);
    final events = await LifeEventRepository(database)
        .listRange(gridStart, gridEnd, relationshipId: profile.id);
    final cycles = await CycleRepository(database).forMonth(profile.id, month);
    final anniversaries =
        await AnniversaryRepository(database).list(relationshipId: profile.id);
    final cycleRepository = CycleRepository(database);
    final cycleKeys = <int>{};
    for (var date = gridStart;
        !date.isAfter(gridEnd);
        date = date.add(const Duration(days: 1))) {
      if (cycles.any((value) => cycleRepository.containsDate(value, date))) {
        cycleKeys.add(DateKeys.toLocalDateKey(date));
      }
    }
    return _RelationshipPageData(
      profiles: profiles,
      profile: profile,
      moods: {for (final value in moods) value.localDate: value},
      events: events,
      cycles: cycles,
      anniversaries: anniversaries,
      cycleDateKeys: cycleKeys,
      anniversaryDateKeys: {
        for (final value in anniversaries)
          if (_monthDateKey(value, month) case final int key) key,
      },
    );
  }

  Future<void> _chooseAdd(AppDatabase database) async {
    final relationshipId = selectedRelationshipId;
    if (relationshipId == null) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('记录 ${selectedDate.month}月${selectedDate.day}日'),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          _AddTile(
            icon: Icons.emoji_emotions_outlined,
            title: '心情',
            value: 'mood',
          ),
          _AddTile(
            icon: Icons.auto_stories_outlined,
            title: '共同事件',
            value: 'event',
          ),
          _AddTile(
            icon: Icons.water_drop_outlined,
            title: '生理期日期',
            value: 'cycle',
          ),
          _AddTile(
            icon: Icons.celebration_outlined,
            title: '纪念日',
            value: 'anniversary',
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
    switch (choice) {
      case 'mood':
        await _recordMood(
          database,
          relationshipId,
          await MoodRepository(database).forDate(
            selectedDate,
            relationshipId: relationshipId,
          ),
        );
      case 'event':
        await _editEvent(database, relationshipId, null);
      case 'cycle':
        final draft = await showCycleDialog(
          context,
          relationshipId: relationshipId,
          selectedDate: selectedDate,
        );
        if (draft != null) await CycleRepository(database).create(draft);
      case 'anniversary':
        final draft = await showAnniversaryDialog(
          context,
          relationshipId: relationshipId,
          initialDate: selectedDate,
        );
        if (draft != null) await AnniversaryRepository(database).create(draft);
    }
    _refresh();
  }

  Future<void> _recordMood(
    AppDatabase database,
    String relationshipId,
    MoodLogEntry? current,
  ) async {
    final draft = await showMoodRecordDialog(
      context,
      date: selectedDate,
      relationshipId: relationshipId,
      current: current,
    );
    if (draft != null) await MoodRepository(database).save(draft);
    _refresh();
  }

  Future<void> _quickSaveMood(
    AppDatabase database,
    String relationshipId,
    String moodCode,
  ) async {
    await MoodRepository(database).save(MoodDraft(
      date: selectedDate,
      moodCode: moodCode,
      intensity: 3,
      relationshipId: relationshipId,
    ));
    _refresh();
  }

  Future<void> _editEvent(
    AppDatabase database,
    String relationshipId,
    LifeEventEntry? current,
  ) async {
    final draft = await showLifeEventDialog(
      context,
      date: selectedDate,
      relationshipId: relationshipId,
      current: current,
    );
    if (draft == null) return;
    final repository = LifeEventRepository(database);
    current == null
        ? await repository.create(draft)
        : await repository.update(current.id, draft);
    _refresh();
  }

  Future<void> _editProfile(
    AppDatabase database,
    RelationshipProfileEntry? current,
  ) async {
    final draft = await showRelationshipDialog(context, current: current);
    if (draft == null) return;
    final repository = RelationshipRepository(database);
    final saved = current == null
        ? await repository.create(draft)
        : await repository.update(current.id, draft);
    selectedRelationshipId = saved.id;
    _refresh();
  }

  Future<void> _archiveProfile(
    AppDatabase database,
    RelationshipProfileEntry value,
  ) async {
    final confirmed = await _confirm('归档“${value.name}”的关系档案？', '归档');
    if (!confirmed) return;
    await RelationshipRepository(database).archive(value.id);
    selectedRelationshipId = null;
    _refresh();
  }

  Future<void> _deleteEvent(AppDatabase database, LifeEventEntry value) async {
    if (!await _confirm('删除“${value.title}”？', '删除')) return;
    await LifeEventRepository(database).delete(value.id);
    _refresh();
  }

  Future<void> _deleteCycle(
      AppDatabase database, CycleRecordEntry value) async {
    if (!await _confirm('删除这段生理期记录？', '删除')) return;
    await CycleRepository(database).delete(value.id);
    _refresh();
  }

  Future<bool> _confirm(String title, String action) async =>
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
              style: action == '删除'
                  ? FilledButton.styleFrom(backgroundColor: Colors.red)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _setMonth(int offset) => setState(() {
        month = DateTime(month.year, month.month + offset);
        selectedDate = DateTime(month.year, month.month, 1);
      });

  Future<void> _chooseDate() async {
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

  void _refresh() {
    if (mounted) setState(() => revision++);
  }
}

class _RelationshipPageData {
  const _RelationshipPageData({
    required this.profiles,
    this.profile,
    this.moods = const {},
    this.events = const [],
    this.cycles = const [],
    this.anniversaries = const [],
    this.cycleDateKeys = const {},
    this.anniversaryDateKeys = const {},
  });

  final List<RelationshipProfileEntry> profiles;
  final RelationshipProfileEntry? profile;
  final Map<int, MoodLogEntry> moods;
  final List<LifeEventEntry> events;
  final List<CycleRecordEntry> cycles;
  final List<AnniversaryEntry> anniversaries;
  final Set<int> cycleDateKeys;
  final Set<int> anniversaryDateKeys;
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pop(context, value),
      );
}

int _daysTogether(int startKey) {
  final start = DateKeys.fromLocalDateKey(startKey);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(start).inDays + 1;
}

bool _occursOn(AnniversaryEntry value, DateTime date) {
  final source = DateKeys.fromLocalDateKey(value.date);
  if (!value.repeatYearly) return value.date == DateKeys.toLocalDateKey(date);
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

Widget _companionshipWidget(BuildContext context, int startDateKey) {
  final days = _daysTogether(startDateKey);
  const milestones = [
    100,
    200,
    365,
    500,
    520,
    1000,
    1314,
    1500,
    2000,
    2500,
    3000,
    5000,
    10000,
  ];
  int? nextMilestone;
  for (final m in milestones) {
    if (m > days) {
      nextMilestone = m;
      break;
    }
  }
  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [
      Text(
        '已经相伴 $days 天',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
      if (nextMilestone != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFDDE9),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '距 $nextMilestone 天还有 ${nextMilestone - days} 天',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFC2185B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}

Widget? _cycleCareBanner(
  BuildContext context,
  AppDatabase database,
  List<CycleRecordEntry> cycles,
) {
  if (cycles.isEmpty) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final repo = CycleRepository(database);
  final inCycle = cycles.any((c) => repo.containsDate(c, today));
  if (inCycle) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBF1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.water_drop, size: 16, color: Color(0xFFE91E63)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '当前处于生理周期关怀期，请多给予温暖与陪伴',
              style: TextStyle(fontSize: 12, color: Color(0xFFC2185B)),
            ),
          ),
        ],
      ),
    );
  }

  final sorted = [...cycles]
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
  final latest = sorted.first;
  final latestStart = DateKeys.fromLocalDateKey(latest.startDate);
  final estimatedNext = latestStart.add(const Duration(days: 28));
  if (estimatedNext.isAfter(today)) {
    final diff = estimatedNext.difference(today).inDays;
    if (diff <= 7) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite, size: 16, color: Color(0xFFE91E63)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '预计生理期约 $diff 天后到来，多准备温水、避免受凉哦',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC2185B)),
              ),
            ),
          ],
        ),
      );
    }
  }
  return null;
}
