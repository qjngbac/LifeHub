import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_series_page.dart';
import 'package:lifehub/features/media/presentation/media_ui_helpers.dart';

class MediaCategoryPage extends ConsumerStatefulWidget {
  const MediaCategoryPage({
    this.category,
    this.initialCategory,
    this.initialStatus,
    super.key,
  });

  /// Backwards-compatible alias for callers that open one category directly.
  final MediaCategory? category;
  final MediaCategory? initialCategory;
  final MediaWatchStatus? initialStatus;

  @override
  ConsumerState<MediaCategoryPage> createState() => _MediaCategoryPageState();
}

class _MediaCategoryPageState extends ConsumerState<MediaCategoryPage> {
  MediaCategory? category;
  MediaWatchStatus? status;
  var revision = 0;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory ?? widget.category;
    status = widget.initialStatus;
  }

  MediaRepository get repository => MediaRepository(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(category?.label ?? status?.label ?? '全部影视'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('添加影视'),
        ),
        body: Column(children: [
          _FilterRow(
            children: [
              ChoiceChip(
                label: const Text('全部分类'),
                selected: category == null,
                onSelected: (_) => setState(() => category = null),
              ),
              for (final value in MediaCategory.values)
                ChoiceChip(
                  label: Text(value.label),
                  selected: category == value,
                  onSelected: (_) => setState(() => category = value),
                ),
            ],
          ),
          _FilterRow(
            children: [
              ChoiceChip(
                label: const Text('全部状态'),
                selected: status == null,
                onSelected: (_) => setState(() => status = null),
              ),
              for (final value in MediaWatchStatus.values)
                ChoiceChip(
                  label: Text(value.label),
                  selected: status == value,
                  onSelected: (_) => setState(() => status = value),
                ),
            ],
          ),
          Expanded(
            child: FutureBuilder<_CategoryData>(
              key: ValueKey(
                '$revision-${category?.dbValue}-${status?.dbValue}',
              ),
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (data.series.isEmpty && data.entries.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(status == null && category == null
                            ? '还没有影视记录'
                            : '没有符合筛选的影视记录'),
                        const SizedBox(height: 12),
                        if (status != null || category != null)
                          OutlinedButton(
                            onPressed: () => setState(() {
                              status = null;
                              category = null;
                            }),
                            child: const Text('清除筛选'),
                          )
                        else
                          FilledButton(
                            onPressed: _add,
                            child: const Text('添加影视'),
                          ),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    if (data.series.isNotEmpty) ...[
                      const _SectionTitle('系列'),
                      for (final series in data.series)
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: mediaCategoryLightColor(
                                    MediaCategory.fromDb(series.category)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                mediaCategoryIcon(
                                    MediaCategory.fromDb(series.category)),
                                color: mediaCategoryColor(
                                    MediaCategory.fromDb(series.category)),
                                size: 22,
                              ),
                            ),
                            title: Text(
                              series.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(_seriesSubtitle(
                              data.entriesBySeries[series.id] ?? const [],
                              matchingCount: data.matchingBySeries[series.id],
                            )),
                            trailing: const Icon(Icons.chevron_right, size: 20),
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
                          onStep: () => _stepEpisode(entry),
                          onTap: () async {
                            final deleted = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MediaEntryPage(entryId: entry.id),
                              ),
                            );
                            if (!context.mounted) return;
                            if (deleted == true) {
                              showDeletedEntryUndo(
                                context,
                                repository,
                                entry,
                                onRestored: () => setState(() => revision++),
                              );
                            }
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
    final series = await repository.listSeries(category: category);
    final allEntries = await repository.listEntries(category: category);
    final visibleEntries = status == null
        ? allEntries
        : allEntries
            .where((entry) => entry.watchStatus == status!.dbValue)
            .toList();
    final visibleSeries = status == null
        ? series
        : series
            .where((item) =>
                visibleEntries.any((entry) => entry.seriesId == item.id))
            .toList();
    return _CategoryData(
      series: visibleSeries,
      entries: visibleEntries.where((entry) => entry.seriesId == null).toList(),
      entriesBySeries: {
        for (final item in visibleSeries)
          item.id:
              allEntries.where((entry) => entry.seriesId == item.id).toList(),
      },
      matchingBySeries: status == null
          ? const {}
          : {
              for (final item in visibleSeries)
                item.id: visibleEntries
                    .where((entry) => entry.seriesId == item.id)
                    .length,
            },
    );
  }

  Future<void> _add() async {
    await showMediaEntryEditor(
      context,
      repository,
      presetCategory: category,
    );
    if (mounted) setState(() => revision++);
  }

  Future<void> _stepEpisode(MediaEntry entry) async {
    final next = entry.completedEpisodes + 1;
    await repository.updateEpisodeProgress(entry.id, next);
    if (mounted) {
      setState(() => revision++);
      final isFinished =
          entry.totalEpisodes != null && next >= entry.totalEpisodes!;
      if (isFinished) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('《${entry.title}》已全部完结！🎉'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

class _CategoryData {
  const _CategoryData({
    required this.series,
    required this.entries,
    required this.entriesBySeries,
    required this.matchingBySeries,
  });
  final List<MediaSeriesEntry> series;
  final List<MediaEntry> entries;
  final Map<String, List<MediaEntry>> entriesBySeries;
  final Map<String, int> matchingBySeries;
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(width: 8),
            ],
          ],
        ),
      );
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
  const _EntryTile({
    required this.entry,
    required this.onTap,
    this.onStep,
  });
  final MediaEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onStep;

  @override
  Widget build(BuildContext context) {
    final category = MediaCategory.fromDb(entry.category);
    final usesEpisodes =
        MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress;
    final isCompleted =
        entry.watchStatus == MediaWatchStatus.completed.dbValue;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: mediaCategoryLightColor(category),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            mediaCategoryIcon(category),
            color: mediaCategoryColor(category),
            size: 22,
          ),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(mediaProgressText(entry)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompleted)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 22),
              )
            else if (usesEpisodes && onStep != null) ...[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(40, 30),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onStep!();
                },
                child: const Text('+1 集',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
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

String _seriesSubtitle(List<MediaEntry> entries, {int? matchingCount}) {
  final completed = entries
      .where((entry) => entry.watchStatus == MediaWatchStatus.completed.dbValue)
      .length;
  final progress = '$completed / ${entries.length} 项完成';
  return matchingCount == null ? progress : '$matchingCount 项符合筛选 · $progress';
}

String _minutes(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return hours == 0
      ? '$minutes 分钟'
      : '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

