import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_ui_helpers.dart';

class MediaSeriesPage extends ConsumerStatefulWidget {
  const MediaSeriesPage({required this.seriesId, super.key});
  final String seriesId;

  @override
  ConsumerState<MediaSeriesPage> createState() => _MediaSeriesPageState();
}

class _MediaSeriesPageState extends ConsumerState<MediaSeriesPage> {
  var revision = 0;
  var reordering = false;
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
                      if (data.entries.length > 1)
                        IconButton(
                          tooltip: reordering ? '完成调整' : '调整顺序',
                          icon: Icon(
                            reordering ? Icons.check : Icons.swap_vert,
                          ),
                          onPressed: () =>
                              setState(() => reordering = !reordering),
                        ),
                      IconButton(
                        tooltip: '批量添加季',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _batchAddSeasons(data.series),
                      ),
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
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('系列里还没有作品'),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () => _addEntry(data.series),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加第一项'),
                                ),
                              ],
                            ),
                          )
                        : Column(children: [
                            Card(
                              elevation: 0,
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: mediaCategoryLightColor(
                                          MediaCategory.fromDb(
                                              data.series.category)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.video_collection_rounded,
                                      color: mediaCategoryColor(
                                          MediaCategory.fromDb(
                                              data.series.category)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${data.summary.completedEntries} / ${data.summary.totalEntries} 项完成',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        if (data.summary.current != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '当前：${data.summary.current!.title}',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        if (data.summary.next != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '下一项：${data.summary.next!.title}',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline,
                                              ),
                                            ),
                                          ),
                                        if (data.summary.totalEntries > 0) ...[
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value:
                                                  data.summary.completedEntries /
                                                      data.summary.totalEntries,
                                              minHeight: 6,
                                            ),
                                          ),
                                        ],
                                        if (data.summary.current != null) ...[
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: FilledButton.tonalIcon(
                                              icon: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  size: 18),
                                              onPressed: () => _openEntry(
                                                data.summary.current!,
                                              ),
                                              label: const Text('继续当前'),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            if (reordering)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('拖动右侧手柄调整观看顺序'),
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
                                  final isCompleted = entry.watchStatus ==
                                      MediaWatchStatus.completed.dbValue;
                                  final isWatching = entry.watchStatus ==
                                      MediaWatchStatus.watching.dbValue;

                                  return Card(
                                    key: ValueKey(entry.id),
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isWatching
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.5)
                                            : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.4),
                                        width: isWatching ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isCompleted
                                            ? Colors.green.withValues(alpha: 0.15)
                                            : isWatching
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                        foregroundColor: isCompleted
                                            ? Colors.green
                                            : isWatching
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onPrimaryContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        child: isCompleted
                                            ? const Icon(Icons.check, size: 18)
                                            : Text('${index + 1}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ),
                                      title: Text(
                                        entry.title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(mediaProgressText(entry)),
                                      trailing: reordering
                                          ? ReorderableDragStartListener(
                                              index: index,
                                              child: const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: Icon(Icons.drag_handle),
                                              ),
                                            )
                                          : const Icon(Icons.chevron_right,
                                              size: 20),
                                      onTap: reordering
                                          ? null
                                          : () => _openEntry(entry),
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

  Future<void> _openEntry(MediaEntry entry) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaEntryPage(entryId: entry.id),
      ),
    );
    if (deleted == true && mounted) {
      showDeletedEntryUndo(
        context,
        repository,
        entry,
        onRestored: () => setState(() => revision++),
      );
    }
    if (mounted) setState(() => revision++);
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

  Future<void> _batchAddSeasons(MediaSeriesEntry series) async {
    final created = await showMediaSeasonBatchEditor(
      context,
      repository,
      series: series,
    );
    if (created == null || !mounted) return;
    setState(() => revision++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 ${created.length} 季')),
    );
  }

  Future<void> _reorder(
      List<MediaEntry> entries, int oldIndex, int newIndex) async {
    final reordered = [...entries];
    final entry = reordered.removeAt(oldIndex);
    final targetIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    reordered.insert(targetIndex, entry);
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
