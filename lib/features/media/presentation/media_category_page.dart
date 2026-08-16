import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_series_page.dart';

class MediaCategoryPage extends ConsumerStatefulWidget {
  const MediaCategoryPage({
    required this.category,
    this.initialStatus,
    super.key,
  });

  final MediaCategory category;
  final MediaWatchStatus? initialStatus;

  @override
  ConsumerState<MediaCategoryPage> createState() => _MediaCategoryPageState();
}

class _MediaCategoryPageState extends ConsumerState<MediaCategoryPage> {
  MediaWatchStatus? status;
  var revision = 0;

  @override
  void initState() {
    super.initState();
    status = widget.initialStatus;
  }

  MediaRepository get repository => MediaRepository(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.category.label)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('添加'),
        ),
        body: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              const SizedBox(width: 8),
              for (final value in MediaWatchStatus.values) ...[
                ChoiceChip(
                  label: Text(value.label),
                  selected: status == value,
                  onSelected: (_) => setState(() => status = value),
                ),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          Expanded(
            child: FutureBuilder<_CategoryData>(
              key: ValueKey('$revision-${status?.dbValue}'),
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (data.series.isEmpty && data.entries.isEmpty) {
                  return Center(child: Text('还没有${widget.category.label}记录'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    if (data.series.isNotEmpty) ...[
                      const _SectionTitle('系列'),
                      for (final series in data.series)
                        Card(
                          child: ListTile(
                            leading: Icon(_categoryIcon(widget.category)),
                            title: Text(series.title),
                            subtitle: Text(_seriesSubtitle(
                                data.entriesBySeries[series.id] ?? const [])),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MediaSeriesPage(seriesId: series.id),
                                ),
                              );
                              if (mounted) setState(() => revision++);
                            },
                          ),
                        ),
                    ],
                    if (data.entries.isNotEmpty) ...[
                      const _SectionTitle('独立作品'),
                      for (final entry in data.entries)
                        _EntryTile(
                          entry: entry,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MediaEntryPage(entryId: entry.id),
                              ),
                            );
                            if (mounted) setState(() => revision++);
                          },
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      );

  Future<_CategoryData> _load() async {
    final series = await repository.listSeries(category: widget.category);
    final allEntries = await repository.listEntries(
      category: widget.category,
      status: status,
    );
    final visibleSeries = status == null
        ? series
        : series
            .where(
                (item) => allEntries.any((entry) => entry.seriesId == item.id))
            .toList();
    return _CategoryData(
      series: visibleSeries,
      entries: allEntries.where((entry) => entry.seriesId == null).toList(),
      entriesBySeries: {
        for (final item in visibleSeries)
          item.id:
              allEntries.where((entry) => entry.seriesId == item.id).toList(),
      },
    );
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.video_collection_outlined),
            title: const Text('添加系列'),
            onTap: () => Navigator.pop(context, 'series'),
          ),
          ListTile(
            leading: const Icon(Icons.movie_outlined),
            title: const Text('添加独立作品'),
            onTap: () => Navigator.pop(context, 'entry'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (choice == 'series') {
      await showMediaSeriesEditor(
        context,
        repository,
        presetCategory: widget.category,
      );
    } else if (choice == 'entry') {
      await showMediaEntryEditor(
        context,
        repository,
        presetCategory: widget.category,
      );
    }
    if (mounted && choice != null) setState(() => revision++);
  }
}

class _CategoryData {
  const _CategoryData({
    required this.series,
    required this.entries,
    required this.entriesBySeries,
  });
  final List<MediaSeriesEntry> series;
  final List<MediaEntry> entries;
  final Map<String, List<MediaEntry>> entriesBySeries;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});
  final MediaEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(_categoryIcon(MediaCategory.fromDb(entry.category))),
          title: Text(entry.title),
          subtitle: Text(mediaProgressText(entry)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

String mediaProgressText(MediaEntry entry) {
  final status = MediaWatchStatus.fromDb(entry.watchStatus).label;
  if (MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress) {
    return entry.totalEpisodes == null
        ? '$status · 已看 ${entry.completedEpisodes} 集'
        : '$status · ${entry.completedEpisodes} / ${entry.totalEpisodes} 集';
  }
  final position = _minutes(entry.playbackPositionSeconds);
  final duration =
      entry.durationSeconds == null ? null : _minutes(entry.durationSeconds!);
  return duration == null
      ? '$status · $position'
      : '$status · $position / $duration';
}

String _seriesSubtitle(List<MediaEntry> entries) {
  final completed = entries
      .where((entry) => entry.watchStatus == MediaWatchStatus.completed.dbValue)
      .length;
  return '$completed / ${entries.length} 部完成';
}

String _minutes(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return hours == 0
      ? '$minutes 分钟'
      : '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

IconData _categoryIcon(MediaCategory category) => switch (category) {
      MediaCategory.tv => Icons.tv_outlined,
      MediaCategory.anime => Icons.animation_outlined,
      MediaCategory.movie => Icons.movie_outlined,
    };
