import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  String state = InboxState.newItem;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = InboxRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('收件箱')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _capture(context, repository),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: InboxState.newItem, label: Text('未处理')),
                ButtonSegment(value: InboxState.later, label: Text('稍后')),
                ButtonSegment(value: InboxState.processed, label: Text('已整理')),
                ButtonSegment(value: InboxState.archived, label: Text('已归档')),
              ],
              selected: {state},
              onSelectionChanged: (values) =>
                  setState(() => state = values.single),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InboxItemEntry>>(
              future: repository.list(state: state),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const Center(child: Text('这里还没有内容'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final canOrganize = state == InboxState.newItem ||
                        state == InboxState.later;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(item.content),
                              subtitle: Text(
                                state == InboxState.processed
                                    ? '${_sourceLabel(item.sourceType)} · ${_convertedLabel(item.convertedType)}'
                                    : _sourceLabel(item.sourceType),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (canOrganize)
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _organize(context, repository, item),
                                    icon:
                                        const Icon(Icons.auto_awesome_outlined),
                                    label: const Text('整理'),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: '更多操作',
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('修改'),
                                    ),
                                    if (state != InboxState.newItem)
                                      const PopupMenuItem(
                                        value: 'new',
                                        child: Text('恢复到未处理'),
                                      ),
                                    if (state != InboxState.later &&
                                        state != InboxState.processed)
                                      const PopupMenuItem(
                                        value: 'later',
                                        child: Text('稍后处理'),
                                      ),
                                    if (state != InboxState.archived)
                                      const PopupMenuItem(
                                        value: 'archive',
                                        child: Text('归档'),
                                      ),
                                  ],
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      await _editContent(
                                        context,
                                        repository,
                                        item,
                                      );
                                      return;
                                    }
                                    await repository.setState(
                                      item.id,
                                      switch (action) {
                                        'new' => InboxState.newItem,
                                        'later' => InboxState.later,
                                        _ => InboxState.archived,
                                      },
                                    );
                                    _refresh();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  void _refresh() => ref.read(refreshProvider.notifier).state++;

  Future<void> _editContent(
    BuildContext context,
    InboxRepository repository,
    InboxItemEntry item,
  ) async {
    final controller = TextEditingController(text: item.content);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('修改收件箱内容'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
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
    if (value == null || value.trim().isEmpty) return;
    await repository.updateContent(item.id, value);
    _refresh();
  }

  Future<void> _organize(
    BuildContext context,
    InboxRepository repository,
    InboxItemEntry item,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          const ListTile(
            title: Text('把这条内容整理为…'),
            subtitle: Text('原文会保留在“已整理”中'),
          ),
          ListTile(
            leading: const Icon(Icons.task_alt_outlined),
            title: const Text('任务'),
            onTap: () => Navigator.pop(context, 'task'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: const Text('清单项'),
            onTap: () => Navigator.pop(context, 'list'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('每日事件'),
            onTap: () => Navigator.pop(context, 'event'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('资料'),
            onTap: () => Navigator.pop(context, 'saved'),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('仅标记已整理'),
            onTap: () => Navigator.pop(context, 'retain'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'task':
        await repository.convertToTask(item.id);
      case 'saved':
        await repository.convertToSavedItem(item.id);
      case 'retain':
        await repository.retain(item.id);
      case 'event':
        if (!context.mounted) return;
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (date == null) return;
        await repository.convertToDailyEvent(item.id, date);
      case 'list':
        if (!context.mounted) return;
        final listId = await _chooseList(context);
        if (listId == null) return;
        await repository.convertToListItem(item.id, listId);
    }
    if (!context.mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已整理，原文保留在已整理分类')),
    );
  }

  Future<String?> _chooseList(BuildContext context) async {
    final lists = await ListRepository(ref.read(databaseProvider)).lists();
    if (!context.mounted) return null;
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建一个清单')),
      );
      return null;
    }
    String selected = lists.first.id;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('选择清单'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: lists
                .map((list) => DropdownMenuItem(
                      value: list.id,
                      child: Text(list.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setLocal(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capture(
    BuildContext context,
    InboxRepository repository,
  ) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('快速收集'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '先记下来，稍后再整理'),
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
    if (value == null || value.trim().isEmpty) return;
    await repository.capture(value);
    _refresh();
  }
}

String _sourceLabel(String value) => switch (value) {
      'ANDROID_SHARE' => '来自 Android 分享',
      'MANUAL' => '手工记录',
      _ => value,
    };

String _convertedLabel(String? value) => switch (value) {
      'TASK' => '已转为任务',
      'LIST_ITEM' => '已转为清单项',
      'LIFE_EVENT' => '已转为每日事件',
      'SAVED_ITEM' => '已存入资料库',
      'RETAINED' => '已保留',
      _ => '已处理',
    };
