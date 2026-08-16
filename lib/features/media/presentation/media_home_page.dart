import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_category_page.dart';
import 'package:lifehub/features/media/presentation/media_editors.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_series_page.dart';

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
          label: const Text('添加'),
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
                                  child: const Text('添加第一部'),
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
                            const _SectionTitle('继续观看'),
                            for (final entry in data.continuing)
                              _ContinueCard(
                                entry: entry,
                                repository: repository,
                                onChanged: _refresh,
                              ),
                          ],
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
                                      count: data.entries
                                          .where((entry) =>
                                              entry.category ==
                                              category.dbValue)
                                          .length,
                                      onTap: () => _openCategory(category),
                                    ))
                                .toList(),
                          ),
                          const _SectionTitle('按状态查看'),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: MediaWatchStatus.values
                                .map((status) => ActionChip(
                                      label: Text(
                                        '${status.label} ${data.entries.where((entry) => entry.watchStatus == status.dbValue).length}',
                                      ),
                                      onPressed: () => _chooseCategory(status),
                                    ))
                                .toList(),
                          ),
                          if (data.recent.isNotEmpty) ...[
                            const _SectionTitle('最近观看'),
                            for (final entry in data.recent.take(10))
                              Card(
                                child: ListTile(
                                  leading: Icon(_categoryIcon(
                                      MediaCategory.fromDb(entry.category))),
                                  title: Text(entry.title),
                                  subtitle: Text(mediaProgressText(entry)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openEntry(entry.id),
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
    final continuing = await repository.continueWatching();
    final recent = entries
        .where((entry) => entry.lastWatchedAt != null)
        .toList()
      ..sort((a, b) => b.lastWatchedAt!.compareTo(a.lastWatchedAt!));
    return _HomeData(
      series: series,
      entries: entries,
      continuing: continuing,
      recent: recent,
    );
  }

  void _refresh() {
    if (mounted) setState(() => revision++);
  }

  Future<void> _openCategory(MediaCategory category,
      [MediaWatchStatus? status]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MediaCategoryPage(category: category, initialStatus: status),
      ),
    );
    _refresh();
  }

  Future<void> _chooseCategory(MediaWatchStatus status) async {
    final category = await showModalBottomSheet<MediaCategory>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: MediaCategory.values
              .map((value) => ListTile(
                    leading: Icon(_categoryIcon(value)),
                    title: Text(value.label),
                    onTap: () => Navigator.pop(context, value),
                  ))
              .toList(),
        ),
      ),
    );
    if (category != null && mounted) await _openCategory(category, status);
  }

  Future<void> _openEntry(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MediaEntryPage(entryId: id)),
    );
    _refresh();
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
            subtitle: const Text('例如某电视剧、动漫或电影系列'),
            onTap: () => Navigator.pop(context, 'series'),
          ),
          ListTile(
            leading: const Icon(Icons.movie_outlined),
            title: const Text('添加独立作品'),
            subtitle: const Text('不需要先创建系列'),
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
      final series = await showMediaSeriesEditor(context, repository);
      if (series != null && mounted) {
        final addFirst = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('添加第一个作品？'),
            content: Text('系列《${series.title}》已创建。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('添加作品'),
              ),
            ],
          ),
        );
        if (addFirst == true && mounted) {
          await showMediaEntryEditor(
            context,
            repository,
            presetCategory: MediaCategory.fromDb(series.category),
            presetSeriesId: series.id,
          );
        }
      }
    } else if (choice == 'entry') {
      await showMediaEntryEditor(context, repository);
    }
    _refresh();
  }
}

class _HomeData {
  const _HomeData({
    required this.series,
    required this.entries,
    required this.continuing,
    required this.recent,
  });
  final List<MediaSeriesEntry> series;
  final List<MediaEntry> entries;
  final List<MediaEntry> continuing;
  final List<MediaEntry> recent;
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
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => result.isSeries
                              ? MediaSeriesPage(seriesId: result.id)
                              : MediaEntryPage(entryId: result.id),
                        ),
                      );
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
  });
  final MediaEntry entry;
  final MediaRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final episodes = MediaEntryType.fromDb(entry.entryType).usesEpisodeProgress;
    final next = episodes
        ? MediaProgressRules.nextEpisode(
            completed: entry.completedEpisodes,
            total: entry.totalEpisodes,
          )
        : null;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MediaEntryPage(entryId: entry.id)),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_categoryIcon(MediaCategory.fromDb(entry.category))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(entry.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(MediaEntryType.fromDb(entry.entryType).label),
            ]),
            const SizedBox(height: 8),
            Text(mediaProgressText(entry)),
            if (next != null) Text('下一集：第 $next 集'),
            if (episodes) ...[
              const SizedBox(height: 8),
              Row(children: [
                IconButton.outlined(
                  onPressed: entry.completedEpisodes == 0
                      ? null
                      : () async {
                          await repository.updateEpisodeProgress(
                              entry.id, entry.completedEpisodes - 1);
                          onChanged();
                        },
                  icon: const Icon(Icons.remove),
                ),
                const Spacer(),
                IconButton.filled(
                  onPressed: next == null
                      ? null
                      : () async {
                          final updated = await repository
                              .updateEpisodeProgress(entry.id, next);
                          if (updated.watchStatus ==
                                  MediaWatchStatus.completed.dbValue &&
                              context.mounted) {
                            final following =
                                await repository.nextEntry(entry.id);
                            if (context.mounted) {
                              final message = following == null
                                  ? '已完成《${entry.title}》'
                                  : '已完成《${entry.title}》；下一部：${following.title}';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(message)),
                              );
                            }
                          }
                          onChanged();
                        },
                  icon: const Icon(Icons.add),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });
  final MediaCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: switch (category) {
          MediaCategory.tv => const Color(0xFFE2E9FF),
          MediaCategory.anime => const Color(0xFFFFE0EB),
          MediaCategory.movie => const Color(0xFFE2F1E8),
        },
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_categoryIcon(category)),
                const Spacer(),
                Text(category.label,
                    style: Theme.of(context).textTheme.titleMedium),
                Text('$count 部', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
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

IconData _categoryIcon(MediaCategory category) => switch (category) {
      MediaCategory.tv => Icons.tv_outlined,
      MediaCategory.anime => Icons.animation_outlined,
      MediaCategory.movie => Icons.movie_outlined,
    };
