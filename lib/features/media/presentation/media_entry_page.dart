import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_ui_helpers.dart';

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
                            elevation: 0,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: mediaCategoryGradient(
                                          MediaCategory.fromDb(
                                              data.entry.category)),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: mediaCategoryLightColor(
                                                MediaCategory.fromDb(
                                                    data.entry.category)),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            mediaCategoryIcon(
                                                MediaCategory.fromDb(
                                                    data.entry.category)),
                                            color: mediaCategoryColor(
                                                MediaCategory.fromDb(
                                                    data.entry.category)),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            data.entry.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.bold),
                                          ),
                                        ),
                                        ActionChip(
                                          avatar: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: mediaStatusColor(
                                                  MediaWatchStatus.fromDb(
                                                      data.entry.watchStatus)),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          label: Text(
                                            '状态：${MediaWatchStatus.fromDb(data.entry.watchStatus).label}',
                                          ),
                                          onPressed: () =>
                                              _changeStatus(data.entry),
                                        ),
                                      ]),
                                      if (data.series != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 8, left: 2),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.collections_bookmark_outlined,
                                                size: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '系列：${data.series!.title}',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      Text(mediaProgressText(data.entry)),
                                      if (data.entry.lastWatchedAt != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '上次观看：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(data.entry.lastWatchedAt!))}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      _ProgressActions(
                                        entry: data.entry,
                                        onEditEpisodes: () =>
                                            _editEpisodes(data.entry),
                                        onNextEpisode: (value) =>
                                            _watchNextEpisode(
                                                data.entry, value),
                                        onMovie: _updateMovie,
                                        onComplete: _complete,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (data.entry.description != null ||
                              data.entry.note != null ||
                              data.entry.rating != null)
                            Card(
                              elevation: 0,
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (data.entry.rating != null) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded,
                                              color: Colors.amber, size: 22),
                                          const SizedBox(width: 4),
                                          Text(
                                            '评分：${data.entry.rating} / 10',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (data.entry.description != null) ...[
                                      const SizedBox(height: 8),
                                      Text(data.entry.description!),
                                    ],
                                    if (data.entry.note != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '备注：${data.entry.note!}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
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
                                title: const Text('下一项'),
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

  Future<void> _editEpisodes(MediaEntry entry) async {
    final value = await showEpisodeProgressDialog(context, entry);
    if (value == null) return;
    await repository.updateEpisodeProgress(entry.id, value);
    if (mounted) setState(() => revision++);
  }

  Future<void> _watchNextEpisode(MediaEntry entry, int value) async {
    await repository.updateEpisodeProgress(entry.id, value);
    if (!mounted) return;
    setState(() => revision++);
  }

  Future<void> _changeStatus(MediaEntry entry) async {
    final selected = await showModalBottomSheet<MediaWatchStatus>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final status in MediaWatchStatus.values)
              ListTile(
                leading: entry.watchStatus == status.dbValue
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(status.label),
                onTap: () => Navigator.pop(sheetContext, status),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected == null || selected.dbValue == entry.watchStatus) return;
    if (selected == MediaWatchStatus.completed) {
      await _complete(entry);
      return;
    }
    if (selected == MediaWatchStatus.plan && _hasProgress(entry)) {
      final reset = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重置观看进度？'),
          content: const Text('改为“想看”会将当前进度重置为 0。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('重置'),
            ),
          ],
        ),
      );
      if (reset != true) return;
      if (MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress) {
        await repository.updateEpisodeProgress(entry.id, 0);
      } else {
        await repository.updateMoviePosition(entry.id, 0);
      }
    }
    await repository.setStatus(entry.id, selected);
    if (mounted) setState(() => revision++);
  }

  Future<void> _updateMovie(MediaEntry entry) async {
    final controller = TextEditingController(
        text: (entry.playbackPositionSeconds ~/ 60).toString());
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改进度'),
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
    required this.onEditEpisodes,
    required this.onNextEpisode,
    required this.onMovie,
    required this.onComplete,
  });
  final MediaEntry entry;
  final VoidCallback onEditEpisodes;
  final ValueChanged<int> onNextEpisode;
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
          label: const Text('修改进度'),
        ),
        FilledButton.tonal(
          onPressed: entry.watchStatus == MediaWatchStatus.completed.dbValue
              ? null
              : () => onComplete(entry),
          child: const Text('标记看完'),
        ),
      ]);
    }
    final next = MediaProgressRules.nextEpisode(
      completed: entry.completedEpisodes,
      total: entry.totalEpisodes,
    );
    final hasTotal = entry.totalEpisodes != null && entry.totalEpisodes! > 0;
    final progressFraction = hasTotal
        ? (entry.completedEpisodes / entry.totalEpisodes!).clamp(0.0, 1.0)
        : 0.0;
    final progressPercent = (progressFraction * 100).toInt();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hasTotal) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '当前进度',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            Text(
              '$progressPercent%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressFraction,
            minHeight: 6,
            backgroundColor:
                Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (next != null)
        Row(
          children: [
            Icon(
              Icons.play_circle_fill_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              '下一集：第 $next 集',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton(
          onPressed: onEditEpisodes,
          child: const Text('修改进度'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: next == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onNextEpisode(next);
                },
          child: Text(next == null ? '已看完' : '看完第 $next 集'),
        ),
      ]),
      if (hasTotal && entry.totalEpisodes! <= 60)
        _EpisodePicker(
          entry: entry,
          onSelectEpisode: onNextEpisode,
        ),
    ]);
  }
}

class _EpisodePicker extends StatefulWidget {
  const _EpisodePicker({
    required this.entry,
    required this.onSelectEpisode,
  });

  final MediaEntry entry;
  final ValueChanged<int> onSelectEpisode;

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  var expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.entry.totalEpisodes!;
    final completed = widget.entry.completedEpisodes;
    final showCount = (total <= 24 || expanded) ? total : 24;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '选集打卡',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            if (total > 24)
              GestureDetector(
                onTap: () => setState(() => expanded = !expanded),
                child: Text(
                  expanded ? '收起' : '展开全部 ($total 集)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(showCount, (index) {
            final ep = index + 1;
            final isCompleted = ep <= completed;
            final isNext = ep == completed + 1;

            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            Color bgColor;
            Color textColor;
            Border? border;

            if (isCompleted) {
              bgColor = colorScheme.primaryContainer;
              textColor = colorScheme.onPrimaryContainer;
            } else if (isNext) {
              bgColor = colorScheme.surface;
              textColor = colorScheme.primary;
              border = Border.all(color: colorScheme.primary, width: 2);
            } else {
              bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
              textColor = colorScheme.onSurfaceVariant;
            }

            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onSelectEpisode(ep);
              },
              child: Container(
                width: 44,
                height: 38,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: border,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isCompleted) ...[
                      Icon(Icons.check, size: 12, color: textColor),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      '$ep',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isNext || isCompleted
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

bool _hasProgress(MediaEntry entry) =>
    MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress
        ? entry.completedEpisodes > 0
        : entry.playbackPositionSeconds > 0;


