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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 8, 12),
                  child: Column(children: [
                    Row(children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFFFDDE9),
                        child: Icon(Icons.favorite_outline),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: profile.id,
                            isExpanded: true,
                            items: data.profiles
                                .map((value) => DropdownMenuItem(
                                      value: value.id,
                                      child: Text(value.nickname?.isNotEmpty ==
                                              true
                                          ? '${value.name} · ${value.nickname}'
                                          : value.name),
                                    ))
                                .toList(),
                            onChanged: (value) => setState(() {
                              selectedRelationshipId = value;
                              revision++;
                            }),
                          ),
                        ),
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
                    ]),
                    if (profile.startDate != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '已经相伴 ${_daysTogether(profile.startDate!)} 天',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ]),
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
              Card(
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
              Text(
                '${selectedDate.month}月${selectedDate.day}日',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Text(
                    mood == null ? '😶' : MoodCatalog.emoji(mood.moodCode),
                    style: const TextStyle(fontSize: 30),
                  ),
                  title: Text(mood == null
                      ? '还没有记录对方心情'
                      : '${MoodCatalog.label(mood.moodCode)} · 强度 ${mood.intensity}/5'),
                  subtitle: mood?.note == null ? null : Text(mood!.note!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _recordMood(database, profile.id, mood),
                ),
              ),
              if (cycles.isNotEmpty)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFD8E6),
                      child: Icon(Icons.water_drop_outlined),
                    ),
                    title: const Text('生理期记录'),
                    subtitle: const Text('当天在手动记录的日期范围内'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (_) => _deleteCycle(database, cycles.first),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child:
                              Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                ),
              ...events.map((value) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFDCE9FF),
                        child: Icon(Icons.auto_stories_outlined),
                      ),
                      title: Text(value.title),
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
                            child:
                                Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                      onTap: () => _editEvent(database, profile.id, value),
                    ),
                  )),
              ...anniversaries.map((value) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFEDBF),
                        child: Icon(Icons.celebration_outlined),
                      ),
                      title: Text(value.title),
                      subtitle: Text(value.repeatYearly ? '每年重复' : '仅此一次'),
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
    final last = DateTime(month.year, month.month + 1, 0);
    final moods = await MoodRepository(database)
        .forMonth(month, relationshipId: profile.id);
    final events = await LifeEventRepository(database)
        .listRange(first, last, relationshipId: profile.id);
    final cycles = await CycleRepository(database).forMonth(profile.id, month);
    final anniversaries =
        await AnniversaryRepository(database).list(relationshipId: profile.id);
    final cycleRepository = CycleRepository(database);
    final cycleKeys = <int>{};
    for (var date = first;
        !date.isAfter(last);
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
