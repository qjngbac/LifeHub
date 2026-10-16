import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_series_page.dart';
import 'package:lifehub/features/media/presentation/media_ui_helpers.dart';

class MediaHomePage extends ConsumerStatefulWidget {
  const MediaHomePage({super.key});

  @override
  ConsumerState<MediaHomePage> createState() => _MediaHomePageState();
}

class _MediaHomePageState extends ConsumerState<MediaHomePage> {
  var query = '';
  var revision = 0;
  MediaRepository get repository => MediaRepository(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('影视进度')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('添加影视'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: '只搜索本模块的系列、作品和备注',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: query.trim().isNotEmpty
                ? _SearchResults(
                    key: ValueKey('$revision-$query'),
                    repository: repository,
                    query: query,
                    onReturn: _refresh,
                  )
                : FutureBuilder<_HomeData>(
                    key: ValueKey(revision),
                    future: _load(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!;
                      if (data.series.isEmpty && data.entries.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.movie_creation_outlined,
                                    size: 64),
                                const SizedBox(height: 16),
                                Text('还没有影视记录',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 8),
                                const Text(
                                  '添加正在看的电视剧、动漫或电影，\n下次就不会忘记看到哪里。',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _add,
                                  child: const Text('添加第一项'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 96),
                        children: [
                          if (data.continuing.isNotEmpty) ...[
                            _SectionTitle(
                              '继续观看',
                              action: data.continuing.length > 5
                                  ? TextButton(
                                      onPressed: () => _openLibrary(
                                        status: MediaWatchStatus.watching,
                                      ),
                                      child: const Text('全部 >'),
                                    )
                                  : null,
                            ),
                            for (final entry in data.continuing.take(5))
                              _ContinueCard(
                                entry: entry,
                                repository: repository,
                                seriesTitle: data.seriesTitleMap[entry.seriesId],
                                onChanged: _refresh,
                              ),
                          ],
                          const _SectionTitle('按状态查看'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: MediaWatchStatus.values
                                .map((status) => ActionChip(
                                      avatar: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: mediaStatusColor(status),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      label: Text(
                                        '${status.label} ${data.entries.where((entry) => entry.watchStatus == status.dbValue).length}',
                                      ),
                                      onPressed: () =>
                                          _openLibrary(status: status),
                                    ))
                                .toList(),
                          ),
                          const _SectionTitle('分类'),
                          GridView.count(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: .92,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: MediaCategory.values
                                .map((category) => _CategoryCard(
                                      category: category,
                                      seriesCount: data.series
                                          .where((series) =>
                                              series.category ==
                                              category.dbValue)
                                          .length,
                                      entryCount: data.entries
                                          .where((entry) =>
                                              entry.category ==
                                              category.dbValue)
                                          .length,
                                      onTap: () =>
                                          _openLibrary(category: category),
                                    ))
                                .toList(),
                          ),
                          if (data.recent.isNotEmpty) ...[
                            const _SectionTitle('最近观看'),
                            for (final entry in data.recent.take(10))
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
                                          MediaCategory.fromDb(entry.category)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      mediaCategoryIcon(
                                          MediaCategory.fromDb(entry.category)),
                                      color: mediaCategoryColor(
                                          MediaCategory.fromDb(entry.category)),
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    entry.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          mediaProgressText(entry),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (entry.lastWatchedAt != null)
                                        Text(
                                          formatRelativeDate(
                                              DateTime.fromMillisecondsSinceEpoch(
                                                  entry.lastWatchedAt!)),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right,
                                      size: 20),
                                  onTap: () => _openEntry(entry),
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ]),
      );

  Future<_HomeData> _load() async {
    final series = await repository.listSeries();
    final entries = await repository.listEntries();
    final continuing = await repository.continueWatching(limit: entries.length);
    final continuingIds = continuing.map((entry) => entry.id).toSet();
    final recent = entries
        .where((entry) =>
            entry.lastWatchedAt != null && !continuingIds.contains(entry.id))
        .toList()
      ..sort((a, b) => b.lastWatchedAt!.compareTo(a.lastWatchedAt!));
    return _HomeData(
      series: series,
      entries: entries,
      continuing: continuing,
      recent: recent,
      seriesTitleMap: {for (final s in series) s.id: s.title},
    );
  }

  void _refresh() {
    if (mounted) setState(() => revision++);
  }

  Future<void> _openLibrary({
    MediaCategory? category,
    MediaWatchStatus? status,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaCategoryPage(
          initialCategory: category,
          initialStatus: status,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _openEntry(MediaEntry entry) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MediaEntryPage(entryId: entry.id)),
    );
    if (deleted == true && mounted) {
      showDeletedEntryUndo(
        context,
        repository,
        entry,
        onRestored: _refresh,
      );
    }
    _refresh();
  }

  Future<void> _add() async {
    await showMediaEntryEditor(context, repository);
    _refresh();
  }
}

class _HomeData {
  const _HomeData({
    required this.series,
    required this.entries,
    required this.continuing,
    required this.recent,
    required this.seriesTitleMap,
  });
  final List<MediaSeriesEntry> series;
  final List<MediaEntry> entries;
  final List<MediaEntry> continuing;
  final List<MediaEntry> recent;
  final Map<String, String> seriesTitleMap;
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.repository,
    required this.query,
    required this.onReturn,
    super.key,
  });
  final MediaRepository repository;
  final String query;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<MediaLocalSearchResult>>(
        future: repository.search(query),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data!;
          if (results.isEmpty) {
            return const Center(child: Text('没有找到相关影视记录'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              const _SectionTitle('模块内搜索结果'),
              for (final result in results)
                Card(
                  child: ListTile(
                    leading: Icon(_categoryIcon(result.category)),
                    title: Text(result.title),
                    subtitle: Text(result.isSeries ? '系列' : '作品'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final entry = result.isSeries
                          ? null
                          : await repository.getEntry(result.id);
                      if (!context.mounted) return;
                      final deleted = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => result.isSeries
                              ? MediaSeriesPage(seriesId: result.id)
                              : MediaEntryPage(entryId: result.id),
                        ),
                      );
                      if (deleted == true && entry != null && context.mounted) {
                        showDeletedEntryUndo(
                          context,
                          repository,
                          entry,
                          onRestored: onReturn,
                        );
                      }
                      onReturn();
                    },
                  ),
                ),
            ],
          );
        },
      );
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.entry,
    required this.repository,
    required this.onChanged,
    this.seriesTitle,
  });
  final MediaEntry entry;
  final MediaRepository repository;
  final VoidCallback onChanged;
  final String? seriesTitle;

  @override
  Widget build(BuildContext context) {
    final category = MediaCategory.fromDb(entry.category);
    final episodes = MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress;
    final next = episodes
        ? MediaProgressRules.nextEpisode(
            completed: entry.completedEpisodes,
            total: entry.totalEpisodes,
          )
        : null;

    final hasTotal = entry.totalEpisodes != null && entry.totalEpisodes! > 0;
    final progressFraction = hasTotal
        ? (entry.completedEpisodes / entry.totalEpisodes!).clamp(0.0, 1.0)
        : 0.0;
    final progressPercent = (progressFraction * 100).toInt();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final deleted = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => MediaEntryPage(entryId: entry.id)),
          );
          if (deleted == true && context.mounted) {
            showDeletedEntryUndo(
              context,
              repository,
              entry,
              onRestored: onChanged,
            );
          }
          onChanged();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部海报色条
            Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: mediaCategoryGradient(category),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧艺术海报图标块
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: mediaCategoryGradient(category),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: mediaCategoryColor(category)
                                  .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            mediaCategoryIcon(category),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 标题、系列和类型
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    MediaEntryType.fromDb(entry.entryType).label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            if (seriesTitle != null && seriesTitle!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.collections_bookmark_outlined,
                                    size: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      seriesTitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              mediaProgressText(entry),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            if (next != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  '下一集：第 $next 集',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasTotal) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$progressPercent%',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ],
                  ),
                  if (hasTotal) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 5,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                  if (episodes) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () async {
                            final value =
                                await showEpisodeProgressDialog(context, entry);
                            if (value == null) return;
                            await repository.updateEpisodeProgress(
                                entry.id, value);
                            onChanged();
                          },
                          child: const Text('修改进度'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: next == null
                              ? null
                              : () async {
                                  HapticFeedback.lightImpact();
                                  final updated = await repository
                                      .updateEpisodeProgress(entry.id, next);
                                  if (!context.mounted) return;
                                  final following = updated.watchStatus ==
                                          MediaWatchStatus.completed.dbValue
                                      ? await repository.nextEntry(entry.id)
                                      : null;
                                  if (!context.mounted) return;
                                  if (following != null) {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(SnackBar(
                                        content: Text(
                                          '已完成《${entry.title}》；下一项：${following.title}',
                                        ),
                                      ));
                                  }
                                  onChanged();
                                },
                          child: Text(next == null ? '已看完' : '看完第 $next 集'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.seriesCount,
    required this.entryCount,
    required this.onTap,
  });
  final MediaCategory category;
  final int seriesCount;
  final int entryCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mediaCategoryColor(category);
    final lightColor = mediaCategoryLightColor(category);
    final gradient = mediaCategoryGradient(category);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                lightColor,
                lightColor.withValues(alpha: 0.65),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -8,
                child: Icon(
                  mediaCategoryIcon(category),
                  size: 68,
                  color: color.withValues(alpha: 0.12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        mediaCategoryIcon(category),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      category.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$seriesCount 个系列 · $entryCount 项',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: action == null
            ? Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold))
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(text,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  action!,
                ],
              ),
      );
}

IconData _categoryIcon(MediaCategory category) => mediaCategoryIcon(category);

