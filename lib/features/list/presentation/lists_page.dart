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
      body: Column(
        children: [
          _buildTemplateChips(context, ref, repository),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<List<ListWithStats>>(
              future: repository.listsWithStats(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('清单加载失败'));
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final listItems = snapshot.data!;
                if (listItems.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.checklist_rtl_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '还没有清单',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点击上方快捷模板一键生成，或点右下角加号新建',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  children: listItems
                      .map((item) {
                        final list = item.list;
                        final isDone = item.isCompleted;
                        final colorScheme = Theme.of(context).colorScheme;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ListDetailPage(list: list),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isDone
                                        ? Colors.green.shade100
                                        : colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      isDone
                                          ? Icons.check_circle_outline
                                          : Icons.checklist,
                                      size: 20,
                                      color: isDone
                                          ? Colors.green.shade800
                                          : colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          list.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              item.total == 0
                                                  ? '空清单'
                                                  : isDone
                                                      ? '已全部完成 (${item.total}项)'
                                                      : '已完成 ${item.checked}/${item.total} 项',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isDone
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isDone
                                                    ? Colors.green.shade700
                                                    : colorScheme.outline,
                                              ),
                                            ),
                                            if (item.total > 0 && !isDone) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '· ${(item.progress * 100).round()}%',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme.outline,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (item.total > 0) ...[
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: item.progress,
                                              minHeight: 4,
                                              backgroundColor: colorScheme
                                                  .surfaceContainerHighest,
                                              valueColor: AlwaysStoppedAnimation(
                                                isDone
                                                    ? Colors.green
                                                    : colorScheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
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
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateChips(
    BuildContext context,
    WidgetRef ref,
    ListRepository repository,
  ) {
    const templates = [
      (name: '购物', icon: Icons.shopping_cart_outlined),
      (name: '逛街', icon: Icons.storefront_outlined),
      (name: '每周采购', icon: Icons.local_grocery_store_outlined),
      (name: '旅行', icon: Icons.flight_takeoff_outlined),
      (name: '健身包', icon: Icons.fitness_center_outlined),
      (name: '面试准备', icon: Icons.work_outline),
      (name: '新生开学', icon: Icons.school_outlined),
      (name: '看病准备', icon: Icons.local_hospital_outlined),
      (name: '露营装备', icon: Icons.terrain_outlined),
      (name: '搬家', icon: Icons.inventory_2_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '快捷模板建单',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: templates
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: Icon(t.icon, size: 14),
                        label: Text(t.name),
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await repository.createFromTemplate(t.name);
                          ref.read(refreshProvider.notifier).state++;
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
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
          IconButton(
            tooltip: '全部重置为未勾选',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('重置清单？'),
                      content: const Text('将所有项目重置为未勾选状态，方便再次循环使用。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('重置')),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirmed) return;
              await repository.resetAllItems(list.id);
              ref.read(refreshProvider.notifier).state++;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已重置所有项目为未勾选')),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'clear_checked',
                child: Text('清除已勾选项'),
              ),
            ],
            onSelected: (action) async {
              if (action == 'clear_checked') {
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
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'list_item_add_${list.id}',
        onPressed: () async {
          final text = await promptText(
            context,
            title: '添加项目',
            label: '内容',
            hintText: '支持多行粘贴，将自动拆分为多项',
            maxLines: 5,
          );
          if (text != null) {
            final lines = text
                .split(RegExp(r'[\r\n]+'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (lines.length > 1) {
              await repository.addItems(list.id, lines);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已批量添加 ${lines.length} 个清单项')),
                );
              }
            } else if (lines.length == 1) {
              await repository.addItem(list.id, lines.first);
            }
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
