import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/evening/data/evening_plan_repository.dart';
import 'package:lifehub/features/event/domain/departure_rules.dart';
import 'package:lifehub/features/weather/data/weather_repository.dart';
import 'package:lifehub/features/weather/presentation/weather_locations_page.dart';

class EveningPlanPage extends ConsumerStatefulWidget {
  const EveningPlanPage({super.key});

  @override
  ConsumerState<EveningPlanPage> createState() => _EveningPlanPageState();
}

class _EveningPlanPageState extends ConsumerState<EveningPlanPage> {
  int revision = 0;
  DateTime get tomorrow {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.read(databaseProvider);
    final repository = EveningPlanRepository(database);
    return Scaffold(
      appBar: AppBar(
        title: const Text('晚间规划'),
        actions: [
          IconButton(
            tooltip: '天气地区',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const WeatherLocationsPage()));
              if (mounted) setState(() => revision++);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPrep(repository),
        icon: const Icon(Icons.add),
        label: const Text('准备项'),
      ),
      body: FutureBuilder<EveningPlan>(
        key: ValueKey(revision),
        future: repository.load(tomorrow),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final plan = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${DateFormat('M月d日 EEEE', 'zh_CN').format(plan.date)} · 明日',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              _WeatherCard(database: database, date: plan.date),
              _Section(
                title: '任务',
                icon: Icons.check_circle_outline,
                empty: '明日没有设置截止时间的待办',
                children: [
                  for (final value in plan.tasks)
                    ListTile(
                      title: Text(value.title),
                      subtitle: Text(value.dueAt == null
                          ? '明日'
                          : DateFormat('HH:mm').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  value.dueAt!))),
                    ),
                ],
              ),
              _Section(
                title: '日程',
                icon: Icons.event_outlined,
                empty: '明日没有日程',
                children: [
                  for (final value in plan.events)
                    ListTile(
                      title: Text(value.title),
                      subtitle: Text(
                        '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(value.startAt))}'
                        '—${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(value.endAt))}'
                        '${value.departureReminderEnabled ? ' · 建议 ${DateFormat('HH:mm').format(DepartureRules.suggestedDepartureAt(start: DateTime.fromMillisecondsSinceEpoch(value.startAt), travelMinutes: value.travelMinutes, preparationMinutes: value.preparationMinutes))} 出发' : ''}',
                      ),
                    ),
                ],
              ),
              _Section(
                title: '课程',
                icon: Icons.school_outlined,
                empty: '明日没有课程',
                children: [
                  for (final value in plan.courses)
                    ListTile(
                      title: Text(value.course.name),
                      subtitle: Text(
                        '${_time(value.schedule.startMinutes)}–${_time(value.schedule.endMinutes)}'
                        '${value.course.room == null ? '' : ' · ${value.course.room}'}',
                      ),
                    ),
                ],
              ),
              _Section(
                title: '待准备清单',
                icon: Icons.backpack_outlined,
                empty: '还没有准备项，仅展示你手工添加或主动关联的内容',
                children: [
                  for (final value in plan.prepItems)
                    CheckboxListTile(
                      value: value.checked,
                      title: Text(value.title),
                      secondary: value.sourceType == null
                          ? null
                          : const Icon(Icons.link),
                      onChanged: (checked) async {
                        await repository.setPrepChecked(
                            value.id, checked ?? false);
                        if (mounted) setState(() => revision++);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addPrep(EveningPlanRepository repository) async {
    final controller = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('添加明日准备项'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '例如：充电宝、证件、材料'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (save == true && controller.text.trim().isNotEmpty) {
      await repository.addPrepItem(tomorrow, controller.text);
      if (mounted) setState(() => revision++);
    }
    controller.dispose();
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.database, required this.date});
  final AppDatabase database;
  final DateTime date;

  @override
  Widget build(BuildContext context) => FutureBuilder<_WeatherResult?>(
        future: _load(),
        builder: (context, snapshot) {
          final value = snapshot.data;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(value?.location.name ?? '天气提示'),
              subtitle: value == null
                  ? const Text('未设置默认地区或天气暂不可用')
                  : Text(
                      '${value.weather.minimumTemperature.round()}–${value.weather.maximumTemperature.round()}℃'
                      ' · 降水概率 ${value.weather.precipitationProbability}%'
                      '${value.weather.stale ? ' · 缓存' : ''}',
                    ),
            ),
          );
        },
      );

  Future<_WeatherResult?> _load() async {
    final repository = WeatherRepository(database);
    final locations = await repository.locations();
    if (locations.isEmpty) return null;
    final location = locations.firstWhere(
      (value) => value.isDefault,
      orElse: () => locations.first,
    );
    try {
      return _WeatherResult(location, await repository.daily(location, date));
    } catch (_) {
      return null;
    }
  }
}

class _WeatherResult {
  const _WeatherResult(this.location, this.weather);
  final WeatherLocationEntry location;
  final DailyWeather weather;
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.icon,
      required this.empty,
      required this.children});
  final String title;
  final IconData icon;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(leading: Icon(icon), title: Text(title)),
            if (children.isEmpty)
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(empty))
            else
              ...children,
          ]),
        ),
      );
}

String _time(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
