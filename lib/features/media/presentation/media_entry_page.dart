import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';

class MediaEntryPage extends ConsumerStatefulWidget {
  const MediaEntryPage({required this.entryId, super.key});
  final String entryId;

  @override
  ConsumerState<MediaEntryPage> createState() => _MediaEntryPageState();
}

class _MediaEntryPageState extends ConsumerState<MediaEntryPage> {
  var revision = 0;
  MediaRepository get repository => MediaRepository(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) => FutureBuilder<_EntryData?>(
        key: ValueKey(revision),
        future: _load(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: Text(data?.entry.title ?? '影视作品'),
              actions: data == null
                  ? null
                  : [
                      IconButton(
                        tooltip: '修改',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(data.entry),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') _delete(data.entry);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child:
                                Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
            ),
            body: snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : data == null
                    ? const Center(child: Text('作品不存在或已删除'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(_icon(MediaCategory.fromDb(
                                        data.entry.category))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        data.entry.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(MediaWatchStatus.fromDb(
                                              data.entry.watchStatus)
                                          .label),
                                    ),
                                  ]),
                                  if (data.series != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text('系列：${data.series!.title}'),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(mediaProgressText(data.entry)),
                                  if (data.entry.lastWatchedAt != null)
                                    Text(
                                      '上次观看：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(data.entry.lastWatchedAt!))}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  const SizedBox(height: 12),
                                  _ProgressActions(
                                    entry: data.entry,
                                    onEpisodes: _updateEpisodes,
                                    onMovie: _updateMovie,
                                    onComplete: _complete,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('观看状态',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: MediaWatchStatus.values
                                        .map((status) => ChoiceChip(
                                              label: Text(status.label),
                                              selected:
                                                  data.entry.watchStatus ==
                                                      status.dbValue,
                                              onSelected: (_) async {
                                                await repository.setStatus(
                                                    data.entry.id, status);
                                                if (mounted) {
                                                  setState(() => revision++);
                                                }
                                              },
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (data.entry.description != null ||
                              data.entry.note != null ||
                              data.entry.rating != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (data.entry.rating != null)
                                      Text('评分：${data.entry.rating} / 10'),
                                    if (data.entry.description != null) ...[
                                      const SizedBox(height: 8),
                                      Text(data.entry.description!),
                                    ],
                                    if (data.entry.note != null) ...[
                                      const SizedBox(height: 8),
                                      Text('备注：${data.entry.note!}'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          if (data.next != null)
                            Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              child: ListTile(
                                leading: const Icon(Icons.skip_next_outlined),
                                title: const Text('下一部'),
                                subtitle: Text(data.next!.title),
                                trailing: TextButton(
                                  onPressed: () async {
                                    await repository.setStatus(data.next!.id,
                                        MediaWatchStatus.watching);
                                    if (mounted) {
                                      Navigator.pushReplacement(
                                        this.context,
                                        MaterialPageRoute(
                                          builder: (_) => MediaEntryPage(
                                              entryId: data.next!.id),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('开始'),
                                ),
                              ),
                            ),
                          AttachmentPanel(
                            entityType: 'MEDIA_ENTRY',
                            entityId: data.entry.id,
                          ),
                        ],
                      ),
          );
        },
      );

  Future<_EntryData?> _load() async {
    final entry = await repository.getEntry(widget.entryId);
    if (entry == null) return null;
    return _EntryData(
      entry: entry,
      series: entry.seriesId == null
          ? null
          : await repository.getSeries(entry.seriesId!),
      next: await repository.nextEntry(entry.id),
    );
  }

  Future<void> _edit(MediaEntry entry) async {
    await showMediaEntryEditor(context, repository, existing: entry);
    if (mounted) setState(() => revision++);
  }

  Future<void> _updateEpisodes(int value) async {
    await repository.updateEpisodeProgress(widget.entryId, value);
    if (mounted) setState(() => revision++);
  }

  Future<void> _updateMovie(MediaEntry entry) async {
    final controller = TextEditingController(
        text: (entry.playbackPositionSeconds ~/ 60).toString());
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新播放位置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '已观看分钟数'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                dialogContext, int.tryParse(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await repository.updateMoviePosition(entry.id, result * 60);
      if (mounted) setState(() => revision++);
    } on RangeError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放位置不能超过总时长')),
        );
      }
    }
  }

  Future<void> _complete(MediaEntry entry) async {
    if (MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress &&
        entry.totalEpisodes != null) {
      await repository.updateEpisodeProgress(entry.id, entry.totalEpisodes!);
    } else if (!MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress &&
        entry.durationSeconds != null) {
      await repository.updateMoviePosition(entry.id, entry.durationSeconds!);
    } else {
      await repository.setStatus(entry.id, MediaWatchStatus.completed);
    }
    if (mounted) setState(() => revision++);
  }

  Future<void> _delete(MediaEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品？'),
        content: Text('删除《${entry.title}》后将不再显示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.deleteEntry(entry.id);
    if (mounted) Navigator.pop(context, true);
  }
}

class _EntryData {
  const _EntryData({required this.entry, this.series, this.next});
  final MediaEntry entry;
  final MediaSeriesEntry? series;
  final MediaEntry? next;
}

class _ProgressActions extends StatelessWidget {
  const _ProgressActions({
    required this.entry,
    required this.onEpisodes,
    required this.onMovie,
    required this.onComplete,
  });
  final MediaEntry entry;
  final ValueChanged<int> onEpisodes;
  final ValueChanged<MediaEntry> onMovie;
  final ValueChanged<MediaEntry> onComplete;

  @override
  Widget build(BuildContext context) {
    final episodes = MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress;
    if (!episodes) {
      return Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => onMovie(entry),
          icon: const Icon(Icons.timelapse),
          label: const Text('更新进度'),
        ),
        FilledButton.tonal(
          onPressed: () => onComplete(entry),
          child: const Text('标记看完'),
        ),
      ]);
    }
    final next = MediaProgressRules.nextEpisode(
      completed: entry.completedEpisodes,
      total: entry.totalEpisodes,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (next != null) Text('下一集：第 $next 集'),
      const SizedBox(height: 8),
      Row(children: [
        IconButton.outlined(
          onPressed: entry.completedEpisodes == 0
              ? null
              : () => onEpisodes(entry.completedEpisodes - 1),
          icon: const Icon(Icons.remove),
        ),
        Expanded(
          child: Text(
            entry.totalEpisodes == null
                ? '已看 ${entry.completedEpisodes} 集'
                : '${entry.completedEpisodes} / ${entry.totalEpisodes}',
            textAlign: TextAlign.center,
          ),
        ),
        IconButton.filled(
          onPressed: next == null ? null : () => onEpisodes(next),
          icon: const Icon(Icons.add),
        ),
      ]),
    ]);
  }
}

IconData _icon(MediaCategory category) => switch (category) {
      MediaCategory.tv => Icons.tv_outlined,
      MediaCategory.anime => Icons.animation_outlined,
      MediaCategory.movie => Icons.movie_outlined,
    };
