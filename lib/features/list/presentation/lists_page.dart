import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/list/data/list_repository.dart';
import 'package:lifehub/shared/ui/create_dialogs.dart';

class ListsPage extends ConsumerWidget {
  const ListsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = ListRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('清单'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '从模板创建',
            icon: const Icon(Icons.auto_awesome_outlined),
            onSelected: (value) async {
              await repository.createFromTemplate(value);
              ref.read(refreshProvider.notifier).state++;
            },
            itemBuilder: (context) => ListRepository.templates.keys
                .map((name) => PopupMenuItem(
                      value: name,
                      child: Text('$name模板'),
                    ))
                .toList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'list_add',
        onPressed: () => createListDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<ListEntry>>(
        future: repository.lists(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('清单加载失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('还没有清单，可以从购物清单开始'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: snapshot.data!
                .map((list) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.checklist),
                        title: Text(list.title),
                        trailing: PopupMenuButton<String>(
                          tooltip: '清单操作',
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                            PopupMenuItem(value: 'archive', child: Text('归档')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                          onSelected: (action) async {
                            if (action == 'rename') {
                              final title = await promptText(
                                context,
                                title: '重命名清单',
                                label: '清单名称',
                                initial: list.title,
                              );
                              if (title != null) {
                                await repository.renameList(list.id, title);
                              }
                            } else if (action == 'archive') {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => AlertDialog(
                                      title: const Text('归档清单？'),
                                      content: Text(list.title),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('归档')),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (confirmed) {
                                await repository.archiveList(list.id);
                              }
                            } else {
                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除清单？'),
                                      content: const Text('清单删除后不会出现在搜索或归档中。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消')),
                                        FilledButton(
                                            style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .error),
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('删除')),
                                      ],
                                    ),
                                  ) ??
                                  false;
                              if (confirmed) {
                                await repository.deleteList(list.id);
                              }
                            }
                            ref.read(refreshProvider.notifier).state++;
                          },
                        ),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ListDetailPage(list: list))),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class ListDetailPage extends ConsumerWidget {
  const ListDetailPage({super.key, required this.list});
  final ListEntry list;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = ListRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: Text(list.title),
        actions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('清空已勾选项？'),
                      content: const Text('已勾选的项目将从当前清单移除。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('清空')),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirmed) return;
              await repository.clearChecked(list.id);
              ref.read(refreshProvider.notifier).state++;
            },
            child: const Text('清除已勾选'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'list_item_add_${list.id}',
        onPressed: () async {
          final text = await promptText(context, title: '添加项目', label: '内容');
          if (text != null) {
            await repository.addItem(list.id, text);
            ref.read(refreshProvider.notifier).state++;
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<ListItemEntry>>(
        future: repository.items(list.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('清单内容加载失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('清单还是空的'));
          }
          final items = snapshot.data!;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: items.length,
            onReorderItem: (oldIndex, newIndex) async {
              final reordered = [...items];
              final moved = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, moved);
              await repository.reorderItems(
                  list.id, reordered.map((item) => item.id).toList());
              ref.read(refreshProvider.notifier).state++;
            },
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                key: ValueKey(item.id),
                child: CheckboxListTile(
                  value: item.checked,
                  title: Text(item.textValue,
                      style: item.checked
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough)
                          : null),
                  onChanged: (checked) async {
                    await repository.toggleItem(item.id,
                        checked: checked == true);
                    ref.read(refreshProvider.notifier).state++;
                  },
                  secondary: IconButton(
                    tooltip: '转为任务',
                    icon: const Icon(Icons.add_task),
                    onPressed: item.checked
                        ? null
                        : () async {
                            await repository.convertItemToTask(item.id);
                            ref.read(refreshProvider.notifier).state++;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已转为任务')),
                              );
                            }
                          },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
