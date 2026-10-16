import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/evening/data/evening_plan_repository.dart';
import 'package:lifehub/features/event/domain/departure_rules.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:lifehub/features/weather/data/weather_repository.dart';
import 'package:lifehub/features/weather/presentation/weather_locations_page.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class EveningPlanPage extends ConsumerStatefulWidget {
  const EveningPlanPage({super.key});

  @override
  ConsumerState<EveningPlanPage> createState() => _EveningPlanPageState();
}

class _EveningPlanPageState extends ConsumerState<EveningPlanPage> {
  int revision = 0;
  int _dayOffset = 1;
  final TextEditingController _prepInputController = TextEditingController();

  @override
  void dispose() {
    _prepInputController.dispose();
    super.dispose();
  }

  DateTime get targetDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: _dayOffset));
  }

  String get _dateTitle {
    return switch (_dayOffset) {
      0 => '今天',
      1 => '明日',
      2 => '后天',
      _ => '规划日',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  builder: (_) => const WeatherLocationsPage(),
                ),
              );
              if (mounted) setState(() => revision++);
            },
          ),
        ],
      ),
      body: FutureBuilder<EveningPlan>(
        key: ValueKey('$revision:$_dayOffset'),
        future: repository.load(targetDate),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final plan = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
            children: [
              // 1. 日期切换药丸选择器
              Center(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('今天')),
                    ButtonSegment(value: 1, label: Text('明天')),
                    ButtonSegment(value: 2, label: Text('后天')),
                  ],
                  selected: {_dayOffset},
                  onSelectionChanged: (val) =>
                      setState(() => _dayOffset = val.first),
                ),
              ),
              const SizedBox(height: 10),

              // 2. 暮色晨瞻 Hero 天气看版
              _WeatherHeroCard(
                database: database,
                date: plan.date,
                dateTitle: _dateTitle,
                onAddSuggestion: (title) async {
                  await repository.addPrepItem(plan.date, title);
                  if (mounted) setState(() => revision++);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已将“$title”加入随身准备清单'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),

              // 3. 今日未完待办安心顺延（温和减压卡片）
              if (plan.overdueTasks.isNotEmpty) ...[
                _buildRolloverCard(context, theme, plan, repository, database),
                const SizedBox(height: 12),
              ],

              // 4. 明日行程与课程聚合时间流
              _TomorrowTimelineCard(
                plan: plan,
                dateTitle: _dateTitle,
                onAddEvent: () async {
                  await createEventDialog(context, ref, initialDate: plan.date);
                  if (mounted) setState(() => revision++);
                },
              ),
              const SizedBox(height: 12),

              // 5. 明日待办任务清单
              _TomorrowTasksCard(
                plan: plan,
                dateTitle: _dateTitle,
                database: database,
                onAddTask: () async {
                  await createTaskDialog(context, ref, dueOn: plan.date);
                  if (mounted) setState(() => revision++);
                },
                onTaskStatusChanged: () {
                  ref.read(refreshProvider.notifier).state++;
                  if (mounted) setState(() => revision++);
                },
              ),
              const SizedBox(height: 12),

              // 6. 出行随身包 · 行前准备清单（彻底重构右下角 FAB 为一体化随身收纳行囊）
              _PrepChecklistCard(
                plan: plan,
                dateTitle: _dateTitle,
                inputController: _prepInputController,
                onAddPrep: (title) async {
                  await repository.addPrepItem(plan.date, title);
                  _prepInputController.clear();
                  if (mounted) setState(() => revision++);
                },
                onToggleChecked: (id, checked) async {
                  await repository.setPrepChecked(id, checked);
                  if (mounted) setState(() => revision++);
                },
                onDeleteItem: (id) async {
                  await repository.deletePrepItem(id);
                  if (mounted) setState(() => revision++);
                },
              ),
              const SizedBox(height: 24),

              // 7. 晚间安睡温馨寄语
              Center(
                child: Text(
                  '今夜好梦 · 祝明日一切顺利 🌙',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRolloverCard(
    BuildContext context,
    ThemeData theme,
    EveningPlan plan,
    EveningPlanRepository repository,
    AppDatabase database,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final containerColor = isDark
        ? const Color(0xFF332005).withValues(alpha: 0.45)
        : const Color(0xFFFFF8E1);
    final borderColor = isDark
        ? Colors.amber.shade700.withValues(alpha: 0.3)
        : Colors.amber.shade300.withValues(alpha: 0.8);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Colors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.overdueTasks.length} 项今日未完待办',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.amber.shade200 : Colors.brown.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '睡前顺延至 $_dateTitle，今晚安心休息',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.amber.shade300.withValues(alpha: 0.8) : Colors.brown.shade600,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final dateTitle = _dateTitle;
              try {
                final count = await repository.deferTasks(
                  plan.overdueTasks.map((t) => t.id).toList(),
                  plan.date,
                );
                try {
                  await NotificationService.instance.rebuildFuture(database);
                } catch (_) {}
                if (!mounted || !context.mounted) return;
                ref.read(refreshProvider.notifier).state++;
                setState(() => revision++);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已将 $count 项待办顺延至 $dateTitle，好好休息！'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('顺延失败：$error')),
                );
              }
            },
            child: Text(
              '顺延至$_dateTitle',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 暮色晨瞻 Hero 天气与建议看板
// ---------------------------------------------------------------------------

class _WeatherHeroCard extends StatelessWidget {
  const _WeatherHeroCard({
    required this.database,
    required this.date,
    required this.dateTitle,
    required this.onAddSuggestion,
  });

  final AppDatabase database;
  final DateTime date;
  final String dateTitle;
  final ValueChanged<String> onAddSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FutureBuilder<_WeatherResult?>(
      future: _load(),
      builder: (context, snapshot) {
        final value = snapshot.data;
        final isRainy = (value?.weather.precipitationProbability ?? 0) >= 30;
        final tempDiff =
            value != null &&
            (value.weather.maximumTemperature -
                    value.weather.minimumTemperature >=
                10);
        final weatherSuggestions = <Widget>[
          if (isRainy)
            _SuggestionChip(
              icon: Icons.umbrella_outlined,
              label: '$dateTitle有雨 · 雨伞',
              color: Colors.blue,
              onTap: () => onAddSuggestion('雨伞'),
            ),
          if (tempDiff)
            _SuggestionChip(
              icon: Icons.thermostat_outlined,
              label: '温差大 · 薄外套',
              color: Colors.purple,
              onTap: () => onAddSuggestion('薄外套'),
            ),
        ];
        final suggestions = <Widget>[
          if (weatherSuggestions.isNotEmpty) weatherSuggestions.first,
          _SuggestionChip(
            icon: Icons.badge_outlined,
            label: '门禁卡 / 证件',
            color: Colors.indigo,
            onTap: () => onAddSuggestion('门禁卡/证件'),
          ),
          ...weatherSuggestions.skip(1),
          _SuggestionChip(
            icon: Icons.battery_charging_full_outlined,
            label: '充电宝',
            color: Colors.teal,
            onTap: () => onAddSuggestion('充电宝'),
          ),
        ];

        final borderColor = isDark
            ? const Color(0xFF4338CA).withValues(alpha: 0.5)
            : const Color(0xFFD1C4E9);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF1E1B4B),
                      const Color(0xFF2E1065),
                      const Color(0xFF1E1B4B),
                    ]
                  : [
                      const Color(0xFFF3E5F5),
                      const Color(0xFFEDE7F6),
                      const Color(0xFFE8EAF6),
                    ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.35)
                    : Colors.purple.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部栏：地区与日期全景
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.nightlight_round,
                              size: 15,
                              color: isDark
                                  ? Colors.indigo.shade200
                                  : Colors.indigo.shade600,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${DateFormat('M月d日 EEEE', 'zh_CN').format(date)} · $dateTitle晨瞻',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isDark
                                      ? Colors.indigo.shade200
                                      : Colors.indigo.shade800,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WeatherLocationsPage(),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    value?.location.name ?? '点击设置默认地区',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.2,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: theme.colorScheme.outline,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value == null
                              ? '地区天气暂不可用，点击选择城市'
                              : '${value.weather.minimumTemperature.round()} ~ ${value.weather.maximumTemperature.round()}℃ · 降水概率 ${value.weather.precipitationProbability}%'
                                    '${value.weather.stale ? ' · 缓存' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isRainy ? '🌧️' : (tempDiff ? '⛅' : '🌙'),
                    style: const TextStyle(fontSize: 36),
                  ),
                ],
              ),

              // 备忘快捷推荐芯片栏
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '出行准备 · 点选加入随身行囊',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final minimumWidth =
                            56 + MediaQuery.textScalerOf(context).scale(12) * 7;
                        final twoColumns =
                            (constraints.maxWidth - 8) / 2 >= minimumWidth;
                        final width = twoColumns
                            ? (constraints.maxWidth - 8) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: suggestions
                              .map(
                                (suggestion) =>
                                    SizedBox(width: width, child: suggestion),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final MaterialColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: isDark
            ? color.shade900.withValues(alpha: 0.3)
            : color.shade50,
        foregroundColor: isDark ? color.shade100 : color.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: isDark
              ? color.shade700.withValues(alpha: 0.4)
              : color.shade200,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isDark ? color.shade200 : color.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? color.shade100 : color.shade800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.add,
            size: 14,
            color: isDark ? color.shade300 : color.shade600,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 明日行程与课程聚合时间流
// ---------------------------------------------------------------------------

sealed class _TimelineEntry {
  final int timeMinutes;
  const _TimelineEntry(this.timeMinutes);
}

class _CourseTimelineEntry extends _TimelineEntry {
  final PlannedCourse plannedCourse;
  _CourseTimelineEntry(this.plannedCourse)
      : super(plannedCourse.schedule.startMinutes);
}

class _EventTimelineEntry extends _TimelineEntry {
  final EventEntry event;
  _EventTimelineEntry(this.event, int startMinutes) : super(startMinutes);
}

class _TomorrowTimelineCard extends StatelessWidget {
  const _TomorrowTimelineCard({
    required this.plan,
    required this.dateTitle,
    required this.onAddEvent,
  });

  final EveningPlan plan;
  final String dateTitle;
  final VoidCallback onAddEvent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final timelineEntries = <_TimelineEntry>[
      ...plan.courses.map((c) => _CourseTimelineEntry(c)),
      ...plan.events.map((e) {
        final dt = DateTime.fromMillisecondsSinceEpoch(e.startAt);
        return _EventTimelineEntry(e, dt.hour * 60 + dt.minute);
      }),
    ];
    timelineEntries.sort((a, b) => a.timeMinutes.compareTo(b.timeMinutes));

    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '$dateTitle行程与课程',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )),
                TextButton.icon(
                  onPressed: onAddEvent,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('日程', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (timelineEntries.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$dateTitle暂无日程与课程安排，全天节奏从容自由',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: timelineEntries.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final entry = timelineEntries[index];
                  if (entry is _CourseTimelineEntry) {
                    final c = entry.plannedCourse;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A1B3D).withValues(alpha: 0.5) : Colors.purple.shade50.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.purple.shade800.withValues(alpha: 0.4) : Colors.purple.shade100,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_time(c.schedule.startMinutes)}–${_time(c.schedule.endMinutes)}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark ? Colors.purple.shade200 : Colors.purple.shade800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 2.5,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.purple.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.course.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (c.course.room != null && c.course.room!.isNotEmpty)
                                  Text(
                                    c.course.room!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.outline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '课程',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.purple.shade300 : Colors.purple.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else if (entry is _EventTimelineEntry) {
                    final e = entry.event;
                    final departureAdvice = e.departureReminderEnabled
                        ? ' · 建议 ${DateFormat('HH:mm').format(DepartureRules.suggestedDepartureAt(start: DateTime.fromMillisecondsSinceEpoch(e.startAt), travelMinutes: e.travelMinutes, preparationMinutes: e.preparationMinutes))} 出发'
                        : '';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.indigo.shade50.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.indigo.shade800.withValues(alpha: 0.4) : Colors.indigo.shade100,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.startAt))}–${DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.endAt))}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark ? Colors.indigo.shade200 : Colors.indigo.shade800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 2.5,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (departureAdvice.isNotEmpty)
                                  Text(
                                    departureAdvice.trim(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '日程',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.indigo.shade300 : Colors.indigo.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 明日待办任务清单
// ---------------------------------------------------------------------------

class _TomorrowTasksCard extends StatelessWidget {
  const _TomorrowTasksCard({
    required this.plan,
    required this.dateTitle,
    required this.database,
    required this.onAddTask,
    required this.onTaskStatusChanged,
  });

  final EveningPlan plan;
  final String dateTitle;
  final AppDatabase database;
  final VoidCallback onAddTask;
  final VoidCallback onTaskStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0.6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$dateTitle待办任务',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (plan.tasks.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${plan.tasks.length} 项',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('待办', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (plan.tasks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🍃 $dateTitle没有设置截止时间的待办任务',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plan.tasks.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final task = plan.tasks[index];
                  final dueText = task.dueAt == null
                      ? dateTitle
                      : DateFormat('HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(task.dueAt!),
                        );

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    leading: IconButton(
                      icon: const Icon(Icons.radio_button_unchecked, size: 20),
                      tooltip: '完成待办',
                      onPressed: () async {
                        await TaskRepository(database).setStatus(task.id, TaskStatus.done);
                        onTaskStatusChanged();
                      },
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      dueText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11.5,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 出行随身包 · 行前准备清单（彻底重构右下角 FAB）
// ---------------------------------------------------------------------------

class _PrepChecklistCard extends StatelessWidget {
  const _PrepChecklistCard({
    required this.plan,
    required this.dateTitle,
    required this.inputController,
    required this.onAddPrep,
    required this.onToggleChecked,
    required this.onDeleteItem,
  });

  final EveningPlan plan;
  final String dateTitle;
  final TextEditingController inputController;
  final ValueChanged<String> onAddPrep;
  final void Function(String id, bool checked) onToggleChecked;
  final ValueChanged<String> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final checkedCount = plan.prepItems.where((p) => p.checked).length;
    final totalCount = plan.prepItems.length;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏：出行随身准备清单
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.backpack_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '出行随身准备清单',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    totalCount == 0 ? '0 项' : '$checkedCount / $totalCount 已就绪',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '睡前收拾好',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 行内快捷输入栏（回车即加，彻底告别突兀悬浮按钮与繁琐弹窗）
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: inputController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '输入$dateTitle要带的物品、材料、证件...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (text) {
                        final trimmed = text.trim();
                        if (trimmed.isNotEmpty) {
                          onAddPrep(trimmed);
                        }
                      },
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final trimmed = inputController.text.trim();
                      if (trimmed.isNotEmpty) {
                        onAddPrep(trimmed);
                      }
                    },
                    child: const Text('添加', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 清单条目列表
            if (plan.prepItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '背包空空，可点击上方天气建议或输入物品添加',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plan.prepItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = plan.prepItems[index];

                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                    ),
                    onDismissed: (_) => onDeleteItem(item.id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: item.checked
                            ? (isDark ? Colors.black.withValues(alpha: 0.2) : Colors.grey.shade100)
                            : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.checked
                              ? Colors.transparent
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.only(left: 6, right: 8),
                        leading: Checkbox(
                          value: item.checked,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (checked) => onToggleChecked(item.id, checked ?? false),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: item.checked ? TextDecoration.lineThrough : null,
                            color: item.checked
                                ? theme.colorScheme.outline
                                : theme.colorScheme.onSurface,
                            fontWeight: item.checked ? FontWeight.normal : FontWeight.w500,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: theme.colorScheme.outline.withValues(alpha: 0.6),
                          ),
                          tooltip: '移除',
                          onPressed: () => onDeleteItem(item.id),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),

            // 底部收拾妥当鼓励提示
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 13, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '随身物品整理妥当，明日出门从容不迫',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _time(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class _WeatherResult {
  const _WeatherResult(this.location, this.weather);
  final WeatherLocationEntry location;
  final DailyWeather weather;
}
