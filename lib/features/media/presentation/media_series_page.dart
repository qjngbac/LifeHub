import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';

class MediaSeriesPage extends ConsumerStatefulWidget {
  const MediaSeriesPage({required this.seriesId, super.key});
  final String seriesId;

  @override
  ConsumerState<MediaSeriesPage> createState() => _MediaSeriesPageState();
}

class _MediaSeriesPageState extends ConsumerState<MediaSeriesPage> {
  var revision = 0;
  MediaRepository get repository => MediaRepository(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) => FutureBuilder<_SeriesData?>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: Text(data?.series.title ?? '影视系列'),
              actions: data == null
                  ? null
                  : [
                      IconButton(
                        tooltip: '修改系列',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(data.series),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') _delete(data.series);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('删除系列',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
            ),
            floatingActionButton: data == null
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _addEntry(data.series),
                    icon: const Icon(Icons.add),
                    label: const Text('添加作品'),
                  ),
            body: snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : data == null
                    ? const Center(child: Text('系列不存在或已删除'))
                    : data.entries.isEmpty
                        ? const Center(child: Text('系列里还没有作品'))
                        : Column(children: [
                            Card(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  const Icon(Icons.video_collection_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${data.summary.completedEntries} / ${data.summary.totalEntries} 部完成',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        if (data.summary.current != null)
                                          Text(
                                              '当前：${data.summary.current!.title}'),
                                        if (data.summary.next != null)
                                          Text(
                                              '下一部：${data.summary.next!.title}'),
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('长按右侧拖动柄可调整观看顺序'),
                              ),
                            ),
                            Expanded(
                              child: ReorderableListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 96),
                                buildDefaultDragHandles: false,
                                itemCount: data.entries.length,
                                onReorderItem: (oldIndex, newIndex) =>
                                    _reorder(data.entries, oldIndex, newIndex),
                                itemBuilder: (context, index) {
                                  final entry = data.entries[index];
                                  return Card(
                                    key: ValueKey(entry.id),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                          child: Text('${index + 1}')),
                                      title: Text(entry.title),
                                      subtitle: Text(mediaProgressText(entry)),
                                      trailing: ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(Icons.drag_handle),
                                        ),
                                      ),
                                      onTap: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => MediaEntryPage(
                                                entryId: entry.id),
                                          ),
                                        );
                                        if (mounted) {
                                          setState(() => revision++);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ]),
          );
        },
      );

  Future<_SeriesData?> _load() async {
    final series = await repository.getSeries(widget.seriesId);
    if (series == null) return null;
    final entries = await repository.listEntries(seriesId: series.id);
    return _SeriesData(
      series: series,
      entries: entries,
      summary: await repository.seriesSummary(series.id),
    );
  }

  Future<void> _edit(MediaSeriesEntry series) async {
    await showMediaSeriesEditor(context, repository, existing: series);
    if (mounted) setState(() => revision++);
  }

  Future<void> _addEntry(MediaSeriesEntry series) async {
    await showMediaEntryEditor(
      context,
      repository,
      presetCategory: MediaCategory.fromDb(series.category),
      presetSeriesId: series.id,
    );
    if (mounted) setState(() => revision++);
  }

  Future<void> _reorder(
      List<MediaEntry> entries, int oldIndex, int newIndex) async {
    final reordered = [...entries];
    final entry = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, entry);
    await repository.reorderEntries(
        widget.seriesId, reordered.map((item) => item.id).toList());
    if (mounted) setState(() => revision++);
  }

  Future<void> _delete(MediaSeriesEntry series) async {
    var deleteEntries = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('删除系列《${series.title}》？'),
          content: RadioGroup<bool>(
            groupValue: deleteEntries,
            onChanged: (value) =>
                setDialogState(() => deleteEntries = value ?? false),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              RadioListTile<bool>(
                value: false,
                title: Text('仅删除系列'),
                subtitle: Text('作品保留并转为独立作品（推荐）'),
              ),
              RadioListTile<bool>(
                value: true,
                title: Text('删除系列及全部作品'),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await repository.deleteSeries(series.id, deleteEntries: deleteEntries);
    if (mounted) Navigator.pop(context, true);
  }
}

class _SeriesData {
  const _SeriesData({
    required this.series,
    required this.entries,
    required this.summary,
  });
  final MediaSeriesEntry series;
  final List<MediaEntry> entries;
  final MediaSeriesSummary summary;
}
