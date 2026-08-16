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
                  child: Text(status == 'PLANNING'
                      ? '暂无旅行计划'
                      : status == 'COMPLETED'
                          ? '还没有完成的旅行'
                          : '还没有归档的旅行'),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '旅行是项目聚合：任务、日程、清单和花费仍使用原模块，不重复存储。',
                      ),
                    ),
                  ),
                  ...trips.map((trip) => FutureBuilder<ProjectEntry>(
                        future: repository.projectFor(trip),
                        builder: (context, project) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(trip.status == 'COMPLETED'
                                  ? Icons.verified_outlined
                                  : Icons.luggage_outlined),
                            ),
                            title: Text(project.data?.name ?? '旅行计划'),
                            subtitle: Text(
                              '${_date(trip.startDate)} - ${_date(trip.endDate)}',
                            ),
                            onTap: project.data == null
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            TripDetailPage(tripId: trip.id),
                                      ),
                                    );
                                    _refresh();
                                  },
                            trailing: PopupMenuButton<String>(
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
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                              onSelected: (action) =>
                                  _tripAction(repository, trip, action),
                            ),
                          ),
                        ),
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
