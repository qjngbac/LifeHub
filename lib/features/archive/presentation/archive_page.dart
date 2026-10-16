import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String selectedType = 'ALL';
  bool isSelecting = false;
  final selectedItems = <String, ArchivedItem>{};
  List<ArchivedItem> _lastDisplayed = const [];

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
      appBar: isSelecting
          ? AppBar(
              leading: IconButton(
                tooltip: '退出选择',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  isSelecting = false;
                  selectedItems.clear();
                }),
              ),
              title: Text('已选择 ${selectedItems.length} 项'),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (selectedItems.length == _lastDisplayed.length &&
                          _lastDisplayed.isNotEmpty) {
                        selectedItems.clear();
                        isSelecting = false;
                      } else {
                        for (final item in _lastDisplayed) {
                          selectedItems['${item.type}:${item.id}'] = item;
                        }
                      }
                    });
                  },
                  child: Text(selectedItems.length == _lastDisplayed.length &&
                          _lastDisplayed.isNotEmpty
                      ? '取消全选'
                      : '全选'),
                ),
              ],
            )
          : AppBar(
              title: const Text('归档'),
              actions: [
                if (showDeleted)
                  IconButton(
                    tooltip: '清空回收站',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _emptyTrash(repository),
                  ),
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
      bottomNavigationBar:
          isSelecting ? _buildSelectionBottomBar(repository) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: queryController,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
            ),
            hintText: showDeleted ? '搜索最近删除...' : '搜索归档内容...',
            leading: const Icon(Icons.search, size: 20),
            trailing: queryController.text.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: '清除',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        queryController.clear();
                        setState(() {});
                      },
                    ),
                  ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.archive_outlined, size: 18),
                  label: Text('归档'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('最近删除'),
                ),
              ],
              selected: {showDeleted},
              onSelectionChanged: (values) => setState(() {
                showDeleted = values.single;
                isSelecting = false;
                selectedItems.clear();
              }),
            ),
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
                _lastDisplayed = const [];
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showDeleted
                            ? Icons.delete_outline_rounded
                            : Icons.archive_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        queryController.text.trim().isEmpty
                            ? (showDeleted ? '最近没有删除内容' : '还没有归档内容')
                            : (showDeleted ? '没有匹配的删除内容' : '没有匹配的归档内容'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                );
              }
              final availableTypes =
                  items.map((e) => e.typeLabel).toSet().toList()..sort();
              final displayed = selectedType == 'ALL'
                  ? items
                  : items.where((e) => e.typeLabel == selectedType).toList();
              _lastDisplayed = displayed;

              return Column(
                children: [
                  if (availableTypes.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: Row(
                        children: [
                          ChoiceChip(
                            showCheckmark: false,
                            label: const Text('全部'),
                            selected: selectedType == 'ALL',
                            onSelected: (selected) {
                              if (selected) setState(() => selectedType = 'ALL');
                            },
                          ),
                          const SizedBox(width: 8),
                          for (final t in availableTypes) ...[
                            ChoiceChip(
                              showCheckmark: false,
                              label: Text(t),
                              selected: selectedType == t,
                              onSelected: (selected) {
                                if (selected) setState(() => selectedType = t);
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  Expanded(
                    child: displayed.isEmpty
                        ? const Center(child: Text('该分类下暂无内容'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: displayed.length,
                            itemBuilder: (context, index) {
                              final item = displayed[index];
                              final itemKey = '${item.type}:${item.id}';
                              final isSelected =
                                  selectedItems.containsKey(itemKey);
                              final updated =
                                  DateTime.fromMillisecondsSinceEpoch(
                                          item.updatedAt,
                                          isUtc: true)
                                      .toLocal();
                              return Card(
                                elevation: isSelected ? 1 : 0,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.5),
                                    width: isSelected ? 1.5 : 0.8,
                                  ),
                                ),
                                color: isSelected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.25)
                                    : null,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    setState(() {
                                      isSelecting = true;
                                      if (isSelected) {
                                        selectedItems.remove(itemKey);
                                        if (selectedItems.isEmpty) {
                                          isSelecting = false;
                                        }
                                      } else {
                                        selectedItems[itemKey] = item;
                                      }
                                    });
                                  },
                                  onTap: () {
                                    if (isSelecting) {
                                      setState(() {
                                        if (isSelected) {
                                          selectedItems.remove(itemKey);
                                          if (selectedItems.isEmpty) {
                                            isSelecting = false;
                                          }
                                        } else {
                                          selectedItems[itemKey] = item;
                                        }
                                      });
                                    }
                                  },
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 4),
                                    leading: isSelecting
                                        ? Checkbox(
                                            value: isSelected,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            onChanged: (_) {
                                              setState(() {
                                                if (isSelected) {
                                                  selectedItems.remove(itemKey);
                                                  if (selectedItems.isEmpty) {
                                                    isSelecting = false;
                                                  }
                                                } else {
                                                  selectedItems[itemKey] = item;
                                                }
                                              });
                                            },
                                          )
                                        : _typeIcon(item.typeLabel, context),
                                    title: Text(
                                      item.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item.typeLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            DateFormat('yyyy-MM-dd HH:mm')
                                                .format(updated),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: isSelecting
                                        ? null
                                        : (showDeleted
                                            ? Wrap(
                                                spacing: 4,
                                                children: [
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8),
                                                    ),
                                                    icon: const Icon(
                                                        Icons
                                                            .restore_from_trash_outlined,
                                                        size: 16),
                                                    label: const Text('恢复'),
                                                    onPressed: () async {
                                                      await repository
                                                          .restoreDeleted(item);
                                                      ref
                                                          .read(refreshProvider
                                                              .notifier)
                                                          .state++;
                                                    },
                                                  ),
                                                  TextButton.icon(
                                                    style: TextButton.styleFrom(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8),
                                                      foregroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .error,
                                                    ),
                                                    icon: const Icon(
                                                        Icons
                                                            .delete_forever_outlined,
                                                        size: 16),
                                                    label: const Text('永久删除'),
                                                    onPressed: () async {
                                                      if (await _confirmPurge(
                                                          context, item)) {
                                                        await repository
                                                            .purgeDeleted(item);
                                                        ref
                                                            .read(refreshProvider
                                                                .notifier)
                                                            .state++;
                                                      }
                                                    },
                                                  ),
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: '恢复此项',
                                                    icon: const Icon(
                                                        Icons.unarchive_outlined,
                                                        size: 20),
                                                    onPressed: () async {
                                                      await repository
                                                          .restore(item);
                                                      ref
                                                          .read(refreshProvider
                                                              .notifier)
                                                          .state++;
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: '移入回收站',
                                                    icon: Icon(
                                                      Icons.delete_outline,
                                                      size: 20,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                    onPressed: () async {
                                                      if (await _confirmDelete(
                                                          context, item)) {
                                                        await repository
                                                            .delete(item);
                                                        ref
                                                            .read(refreshProvider
                                                                .notifier)
                                                            .state++;
                                                      }
                                                    },
                                                  ),
                                                ],
                                              )),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildSelectionBottomBar(ArchiveRepository repository) {
    final theme = Theme.of(context);
    final count = selectedItems.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: showDeleted
              ? [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restore_from_trash_outlined,
                          size: 18),
                      label: Text('批量恢复 ($count)'),
                      onPressed: count == 0
                          ? null
                          : () => _batchRestoreDeleted(repository),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_forever_outlined, size: 18),
                      label: Text('彻底删除 ($count)'),
                      onPressed: count == 0
                          ? null
                          : () => _batchPurgeDeleted(repository),
                    ),
                  ),
                ]
              : [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.unarchive_outlined, size: 18),
                      label: Text('批量恢复 ($count)'),
                      onPressed:
                          count == 0 ? null : () => _batchRestore(repository),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text('批量删除 ($count)'),
                      onPressed:
                          count == 0 ? null : () => _batchDelete(repository),
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  Future<void> _batchRestore(ArchiveRepository repository) async {
    final items = selectedItems.values.toList();
    for (final item in items) {
      await repository.restore(item);
    }
    _finishBatch('已恢复 ${items.length} 项内容');
  }

  Future<void> _batchDelete(ArchiveRepository repository) async {
    final items = selectedItems.values.toList();
    final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('批量删除 ${items.length} 项？'),
            content: const Text('选中的内容将移入最近删除，可在 30 天内恢复。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm && mounted) {
      for (final item in items) {
        await repository.delete(item);
      }
      _finishBatch('已移入最近删除 ${items.length} 项');
    }
  }

  Future<void> _batchRestoreDeleted(ArchiveRepository repository) async {
    final items = selectedItems.values.toList();
    for (final item in items) {
      await repository.restoreDeleted(item);
    }
    _finishBatch('已恢复 ${items.length} 项内容');
  }

  Future<void> _batchPurgeDeleted(ArchiveRepository repository) async {
    final items = selectedItems.values.toList();
    final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text('彻底永久删除 ${items.length} 项？'),
            content: const Text('永久删除后无法恢复，确定彻底删除吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('永久删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm && mounted) {
      for (final item in items) {
        await repository.purgeDeleted(item);
      }
      _finishBatch('已彻底删除 ${items.length} 项');
    }
  }

  void _finishBatch(String message) {
    if (!mounted) return;
    setState(() {
      isSelecting = false;
      selectedItems.clear();
    });
    ref.read(refreshProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _emptyTrash(ArchiveRepository repository) async {
    final items = await repository.deletedItems();
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回收站为空，无需清空')),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('清空回收站？'),
            content: Text('将彻底永久删除回收站内的全部 ${items.length} 项内容，此操作无法撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) {
      for (final item in items) {
        await repository.purgeDeleted(item);
      }
      ref.read(refreshProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回收站已清空')),
      );
    }
  }

  Widget _typeIcon(String typeLabel, BuildContext context) {
    final (IconData icon, Color color) = switch (typeLabel) {
      '任务' => (Icons.check_circle_outline_rounded, const Color(0xFF3F51B5)),
      '目标' => (Icons.flag_outlined, const Color(0xFFE91E63)),
      '项目' => (Icons.folder_outlined, const Color(0xFFFF9800)),
      '便签' => (Icons.description_outlined, const Color(0xFF009688)),
      '日程' || '日历' => (Icons.event_outlined, const Color(0xFF9C27B0)),
      '随身清单' => (Icons.inventory_2_outlined, const Color(0xFF00ACC1)),
      _ => (Icons.archive_outlined, const Color(0xFF607D8B)),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
