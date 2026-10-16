import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';
import 'package:lifehub/features/trip/presentation/trip_detail_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class TripsPage extends ConsumerStatefulWidget {
  const TripsPage({super.key});

  @override
  ConsumerState<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends ConsumerState<TripsPage> {
  String status = 'PLANNING';

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = TripRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('旅行')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, repository),
        icon: const Icon(Icons.add),
        label: const Text('创建旅行'),
      ),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'PLANNING', label: Text('计划中')),
              ButtonSegment(value: 'COMPLETED', label: Text('已完成')),
              ButtonSegment(value: 'ARCHIVED', label: Text('已归档')),
            ],
            selected: {status},
            onSelectionChanged: (value) =>
                setState(() => status = value.single),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<TripProfileEntry>>(
            future: repository.list(statuses: {status}),
            builder: (context, snapshot) {
              final trips = snapshot.data ?? const <TripProfileEntry>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (trips.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.flight_takeoff_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          status == 'PLANNING'
                              ? '暂无旅行计划'
                              : status == 'COMPLETED'
                                  ? '还没有完成的旅行'
                                  : '还没有归档的旅行',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '将行前任务、每日行程、随身清单与花费账单全景聚合。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        if (status == 'PLANNING') ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _create(context, repository),
                            icon: const Icon(Icons.add),
                            label: const Text('开启新旅程'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '旅行是项目聚合：任务、日程、清单和花费深度联动，不重复存储。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...trips.map((trip) => FutureBuilder<TripOverview>(
                        future: repository.overview(trip.id),
                        builder: (context, overviewSnapshot) {
                          final overview = overviewSnapshot.data;
                          final projectName = overview?.project.name ?? '旅行计划';
                          final tasksCount = overview?.tasks.length ?? 0;
                          final doneTasks = overview?.tasks
                                  .where((t) => t.status == 'DONE')
                                  .length ??
                              0;
                          final eventsCount = (overview?.events.length ?? 0) +
                              (overview?.lifeEvents.length ?? 0);
                          final placesCount = overview?.locations.length ?? 0;
                          final expensesCount = overview?.expenses.length ?? 0;
                          final totalDays = DateKeys.fromLocalDateKey(
                                      trip.endDate)
                                  .difference(DateKeys.fromLocalDateKey(
                                      trip.startDate))
                                  .inDays +
                              1;

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TripDetailPage(tripId: trip.id),
                                  ),
                                );
                                _refresh();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: (trip.status == 'COMPLETED'
                                                    ? Colors.green
                                                    : Colors.teal)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            trip.status == 'COMPLETED'
                                                ? Icons.verified_outlined
                                                : Icons.luggage_outlined,
                                            color: trip.status == 'COMPLETED'
                                                ? Colors.green
                                                : Colors.teal,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                projectName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_date(trip.startDate)} - ${_date(trip.endDate)} · 共 $totalDays 天',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _tripStatusBadge(context, trip),
                                        PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          iconSize: 20,
                                          itemBuilder: (_) => [
                                            if (trip.status == 'PLANNING')
                                              const PopupMenuItem(
                                                value: 'complete',
                                                child: Text('标记完成'),
                                              ),
                                            if (trip.status == 'ARCHIVED')
                                              const PopupMenuItem(
                                                value: 'restore',
                                                child: Text('恢复到计划中'),
                                              )
                                            else
                                              const PopupMenuItem(
                                                value: 'archive',
                                                child: Text('归档'),
                                              ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ),
                                          ],
                                          onSelected: (action) =>
                                              _tripAction(repository, trip, action),
                                        ),
                                      ],
                                    ),
                                    if (overview != null &&
                                        (tasksCount > 0 ||
                                            eventsCount > 0 ||
                                            placesCount > 0 ||
                                            expensesCount > 0)) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          if (tasksCount > 0)
                                            _metricPill(
                                              Icons.check_circle_outline,
                                              '任务 $doneTasks/$tasksCount',
                                              doneTasks == tasksCount
                                                  ? Colors.green
                                                  : Colors.blue,
                                            ),
                                          if (eventsCount > 0)
                                            _metricPill(
                                              Icons.calendar_today_outlined,
                                              '行程 $eventsCount 项',
                                              Colors.purple,
                                            ),
                                          if (placesCount > 0)
                                            _metricPill(
                                              Icons.place_outlined,
                                              '地点 $placesCount 处',
                                              Colors.orange,
                                            ),
                                          if (expensesCount > 0)
                                            _metricPill(
                                              Icons.payments_outlined,
                                              '账单 $expensesCount 笔',
                                              Colors.teal,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  void _refresh() => ref.read(refreshProvider.notifier).state++;

  Widget _tripStatusBadge(BuildContext context, TripProfileEntry trip) {
    if (trip.status == 'COMPLETED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('已完成',
            style: TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.bold)),
      );
    }
    if (trip.status == 'ARCHIVED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('已归档',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateKeys.fromLocalDateKey(trip.startDate);
    final end = DateKeys.fromLocalDateKey(trip.endDate);

    if (today.isBefore(start)) {
      final diff = start.difference(today).inDays;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          diff == 0 ? '今天出发 🛫' : '还有 $diff 天出发',
          style: const TextStyle(
              fontSize: 11,
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold),
        ),
      );
    } else if (!today.isAfter(end)) {
      final currentDay = today.difference(start).inDays + 1;
      final totalDays = end.difference(start).inDays + 1;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '旅途中 ($currentDay/$totalDays天) 🧳',
          style: const TextStyle(
              fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('待总结',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
      );
    }
  }

  Future<void> _tripAction(
    TripRepository repository,
    TripProfileEntry trip,
    String action,
  ) async {
    switch (action) {
      case 'complete':
        await repository.complete(trip.id);
      case 'archive':
        await repository.archive(trip.id);
      case 'restore':
        await repository.restore(trip.id);
      case 'delete':
        final choice = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('删除旅行'),
            content: const Text(
              '可以只删除旅行聚合，保留原项目与任务；也可以同时删除项目。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留项目'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('同时删除项目'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        await repository.delete(trip.id, deleteProject: choice);
    }
    _refresh();
  }

  Future<void> _create(
    BuildContext context,
    TripRepository repository,
  ) async {
    final name = TextEditingController();
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 2));
    var template = 'CITY';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => KeyboardSafeFormDialog(
          title: const Text('创建旅行'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '旅行名称'),
            ),
            ListTile(
              title: const Text('开始日期'),
              subtitle: Text(DateFormat('yyyy-MM-dd').format(start)),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDate: start,
                );
                if (value != null) {
                  setLocal(() {
                    start = value;
                    if (end.isBefore(start)) end = start;
                  });
                }
              },
            ),
            ListTile(
              title: const Text('结束日期'),
              subtitle: Text(DateFormat('yyyy-MM-dd').format(end)),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: start,
                  lastDate: DateTime(2100),
                  initialDate: end.isBefore(start) ? start : end,
                );
                if (value != null) setLocal(() => end = value);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: template,
              decoration: const InputDecoration(labelText: '行前模板'),
              items: const [
                DropdownMenuItem(value: 'CITY', child: Text('城市旅行')),
                DropdownMenuItem(value: 'OUTDOOR', child: Text('户外出行')),
                DropdownMenuItem(value: 'NONE', child: Text('不使用模板')),
              ],
              onChanged: (value) => setLocal(() => template = value!),
            ),
            const SizedBox(height: 8),
            Text(
              _templatePreview(template),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || name.text.trim().isEmpty) return;
    final trip = await repository.create(
      TripDraft(name: name.text, startDate: start, endDate: end),
    );
    await repository.applyTemplate(trip.id, template);
    _refresh();
  }
}

String _templatePreview(String template) => switch (template) {
      'OUTDOOR' => '将创建户外装备清单，并添加天气、路线和紧急联系人准备任务。',
      'CITY' => '将创建证件、充电器等装备清单，并添加交通与住宿确认任务。',
      _ => '仅创建空白旅行项目。',
    };

String _date(int key) =>
    DateFormat('MM月d日').format(DateKeys.fromLocalDateKey(key));

Widget _metricPill(IconData icon, String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}
