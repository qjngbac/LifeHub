import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/archive/data/archive_repository.dart';
import 'package:lifehub/features/search/presentation/search_page.dart';

class ArchivePage extends ConsumerStatefulWidget {
  const ArchivePage({super.key});

  @override
  ConsumerState<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends ConsumerState<ArchivePage> {
  final queryController = TextEditingController();
  bool showDeleted = false;

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = ArchiveRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        title: const Text('归档'),
        actions: [
          IconButton(
            tooltip: '搜索当前数据',
            icon: const Icon(Icons.travel_explore),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: queryController,
            decoration: InputDecoration(
              hintText: showDeleted ? '搜索最近删除' : '搜索归档内容',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: queryController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除',
                      onPressed: () {
                        queryController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('归档')),
              ButtonSegment(value: true, label: Text('最近删除')),
            ],
            selected: {showDeleted},
            onSelectionChanged: (values) =>
                setState(() => showDeleted = values.single),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ArchivedItem>>(
            future: showDeleted
                ? repository.deletedItems(query: queryController.text)
                : repository.list(query: queryController.text),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('归档内容加载失败'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return Center(
                  child: Text(queryController.text.trim().isEmpty
                      ? (showDeleted ? '最近没有删除内容' : '还没有归档内容')
                      : (showDeleted ? '没有匹配的删除内容' : '没有匹配的归档内容')),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final updated = DateTime.fromMillisecondsSinceEpoch(
                          item.updatedAt,
                          isUtc: true)
                      .toLocal();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(item.typeLabel[0])),
                      title: Text(item.title),
                      subtitle: Text(
                          '${item.typeLabel} · ${DateFormat('yyyy-MM-dd').format(updated)}'),
                      trailing: showDeleted
                          ? Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    await repository.restoreDeleted(item);
                                    ref.read(refreshProvider.notifier).state++;
                                  },
                                  child: const Text('恢复'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    if (await _confirmPurge(context, item)) {
                                      await repository.purgeDeleted(item);
                                      ref
                                          .read(refreshProvider.notifier)
                                          .state++;
                                    }
                                  },
                                  child: const Text(
                                    '永久删除',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            )
                          : PopupMenuButton<String>(
                              tooltip: '归档操作',
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'restore', child: Text('恢复')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                              onSelected: (action) async {
                                if (action == 'restore') {
                                  await repository.restore(item);
                                } else if (await _confirmDelete(
                                    context, item)) {
                                  await repository.delete(item);
                                }
                                ref.read(refreshProvider.notifier).state++;
                              },
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, ArchivedItem item) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('删除${item.typeLabel}？'),
            content: Text('“${item.title}”会移入最近删除，可在 30 天内恢复。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmPurge(BuildContext context, ArchivedItem item) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('永久删除${item.typeLabel}？'),
            content: Text('“${item.title}”永久删除后无法恢复。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('永久删除')),
            ],
          ),
        ) ??
        false;
  }
}
