import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';
import 'package:lifehub/features/trip/presentation/trip_expense_page.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class TripDetailPage extends ConsumerWidget {
  const TripDetailPage({required this.tripId, super.key});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = TripRepository(ref.read(databaseProvider));
    return FutureBuilder<TripOverview>(
      future: repository.overview(tripId),
      builder: (context, snapshot) {
        final value = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: Text(value?.project.name ?? '旅行详情')),
          body: value == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  '${_date(value.trip.startDate)} - ${_date(value.trip.endDate)}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Chip(label: Text(_status(value.trip.status))),
                            ]),
                            const SizedBox(height: 8),
                            Text(
                              '项目聚合 · ${value.tasks.length} 个任务 · '
                              '${value.events.length} 个日程 · ${value.lists.length} 个清单',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (value.trip.status == 'COMPLETED')
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.rate_review_outlined),
                          title: const Text('旅后复盘'),
                          subtitle: Text(
                              value.trip.notes?.trim().isNotEmpty == true
                                  ? value.trip.notes!
                                  : '记下此行的收获、遗憾和下次建议'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _review(
                            context,
                            ref,
                            repository,
                            value.trip.notes,
                          ),
                        ),
                      ),
                    _Section(
                      title: '行前任务',
                      icon: Icons.check_circle_outline,
                      onAdd: () => _chooseLink(
                        context,
                        ref,
                        repository,
                        'TASK',
                      ),
                      children: value.tasks.isEmpty
                          ? const [Text('可在任务模块中选择该旅行项目')]
                          : value.tasks
                              .map((task) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(task.status == 'DONE'
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked),
                                    title: Text(task.title),
                                  ))
                              .toList(),
                    ),
                    _Section(
                      title: '按日期的行程',
                      icon: Icons.event_note_outlined,
                      onAdd: () => _chooseLink(
                        context,
                        ref,
                        repository,
                        'EVENT',
                      ),
                      children: _datedItems(value),
                    ),
                    _Section(
                      title: '地点',
                      icon: Icons.place_outlined,
                      onAdd: () => _chooseLink(
                        context,
                        ref,
                        repository,
                        'LOCATION',
                      ),
                      children: value.locations.isEmpty
                          ? const [Text('可从地点库关联景点、餐厅和交通点')]
                          : value.locations
                              .map((place) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(place.name),
                                    subtitle: Text(place.address ?? ''),
                                  ))
                              .toList(),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: const Text('旅行账单'),
                        subtitle: Text(
                          '${value.expenses.length} 笔花费，不自动换算币种',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TripExpensePage(tripId: tripId),
                          ),
                        ),
                      ),
                    ),
                    EntityRelationsPanel(
                      entity: EntityReference(type: 'TRIP', id: tripId),
                    ),
                    AttachmentPanel(entityType: 'TRIP', entityId: tripId),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _datedItems(TripOverview value) {
    final rows = <(DateTime, String, String)>[
      ...value.events.map((event) => (
            DateTime.fromMillisecondsSinceEpoch(event.startAt, isUtc: true)
                .toLocal(),
            event.title,
            DateFormat.Hm().format(
              DateTime.fromMillisecondsSinceEpoch(event.startAt, isUtc: true)
                  .toLocal(),
            ),
          )),
      ...value.lifeEvents.map((event) => (
            DateKeys.fromLocalDateKey(event.localDate),
            event.title,
            event.timeMinutes == null
                ? '全天'
                : '${(event.timeMinutes! ~/ 60).toString().padLeft(2, '0')}:'
                    '${(event.timeMinutes! % 60).toString().padLeft(2, '0')}',
          )),
    ]..sort((left, right) => left.$1.compareTo(right.$1));
    if (rows.isEmpty) return const [Text('还没有关联的行程')];
    DateTime? lastDay;
    final widgets = <Widget>[];
    for (final row in rows) {
      final day = DateTime(row.$1.year, row.$1.month, row.$1.day);
      if (lastDay != day) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            DateFormat('M月d日 EEEE', 'zh_CN').format(day),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ));
        lastDay = day;
      }
      widgets.add(ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(row.$2),
        trailing: Text(row.$3),
      ));
    }
    return widgets;
  }

  Future<void> _chooseLink(
    BuildContext context,
    WidgetRef ref,
    TripRepository repository,
    String type,
  ) async {
    final candidates = await repository.linkCandidates(tripId, type);
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: candidates.isEmpty
            ? ListTile(
                title: const Text('没有可关联的内容'),
                subtitle:
                    Text(type == 'LOCATION' ? '请先在地点模块添加地点' : '只显示旅行日期范围内的内容'),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('选择要关联的内容'),
                    trailing: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  for (final candidate in candidates)
                    ListTile(
                      title: Text(candidate.title),
                      subtitle: candidate.subtitle == null
                          ? null
                          : Text(candidate.subtitle!),
                      onTap: () => Navigator.pop(context, candidate.id),
                    ),
                ],
              ),
      ),
    );
    if (selected == null) return;
    await repository.link(tripId, type, selected);
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    TripRepository repository,
    String? initial,
  ) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('旅后复盘'),
        content: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 9,
          decoration: const InputDecoration(
            hintText: '最喜欢什么？有什么遗憾？下次会怎样安排？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await repository.savePostTripReview(tripId, result);
    ref.read(refreshProvider.notifier).state++;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.onAdd,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (onAdd != null)
                  IconButton(
                    tooltip: '关联已有内容',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_link),
                  ),
              ]),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
}

String _status(String value) => switch (value) {
      'COMPLETED' => '已完成',
      'ARCHIVED' => '已归档',
      _ => '计划中',
    };

String _date(int key) =>
    DateFormat('yyyy年M月d日').format(DateKeys.fromLocalDateKey(key));
