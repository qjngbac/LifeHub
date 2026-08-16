import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';

void main() {
  late AppDatabase database;
  late MediaRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MediaRepository(database);
  });

  tearDown(() => database.close());

  test('stores series and independent entries with local module search',
      () async {
    final series = await repository.createSeries(const MediaSeriesDraft(
      title: '银河系列',
      category: MediaCategory.anime,
      note: '推荐观看顺序',
    ));
    await repository.createEntry(MediaEntryDraft(
      title: '银河第一季',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      totalEpisodes: 12,
    ));
    final independent = await repository.createEntry(const MediaEntryDraft(
      title: '独立纪录片',
      category: MediaCategory.movie,
      entryType: MediaEntryType.documentary,
      durationSeconds: 5400,
      note: '关于雪山',
    ));

    expect((await repository.listSeries()).single.id, series.id);
    expect((await repository.listEntries(seriesId: series.id)).length, 1);
    expect(
      (await repository.listEntries(category: MediaCategory.movie)).single.id,
      independent.id,
    );
    final search = await repository.search('雪山');
    expect(search.map((item) => item.id), contains(independent.id));
  });

  test('episode progress drives status and continue-watching order', () async {
    final first = await repository.createEntry(const MediaEntryDraft(
      title: '第一部',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 2,
    ));
    final second = await repository.createEntry(const MediaEntryDraft(
      title: '第二部',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 10,
    ));
    final early = DateTime.utc(2026, 8, 10, 20);
    final late = DateTime.utc(2026, 8, 11, 20);

    await repository.updateEpisodeProgress(first.id, 1, now: early);
    await repository.updateEpisodeProgress(second.id, 3, now: late);
    final continuing = await repository.continueWatching();
    expect(continuing.map((item) => item.id), [second.id, first.id]);

    final completed =
        await repository.updateEpisodeProgress(first.id, 2, now: late);
    expect(completed.watchStatus, MediaWatchStatus.completed.dbValue);
    expect(completed.completedAt, late.millisecondsSinceEpoch);
    expect((await repository.continueWatching()).map((item) => item.id),
        isNot(contains(first.id)));
  });

  test('movie position obeys duration and starts watching', () async {
    final movie = await repository.createEntry(const MediaEntryDraft(
      title: '长电影',
      category: MediaCategory.movie,
      entryType: MediaEntryType.movie,
      durationSeconds: 7200,
    ));

    final updated = await repository.updateMoviePosition(movie.id, 3600);
    expect(updated.playbackPositionSeconds, 3600);
    expect(updated.watchStatus, MediaWatchStatus.watching.dbValue);
    expect(
        () => repository.updateMoviePosition(movie.id, 7201), throwsRangeError);
  });

  test('custom series order controls the next unfinished entry', () async {
    final series = await repository.createSeries(
      const MediaSeriesDraft(title: '观看顺序', category: MediaCategory.anime),
    );
    final a = await repository.createEntry(MediaEntryDraft(
      title: '第一季',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      totalEpisodes: 1,
    ));
    final b = await repository.createEntry(MediaEntryDraft(
      title: '剧场版',
      category: MediaCategory.anime,
      entryType: MediaEntryType.movie,
      seriesId: series.id,
      durationSeconds: 6000,
    ));
    final c = await repository.createEntry(MediaEntryDraft(
      title: '第二季',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      totalEpisodes: 12,
    ));

    await repository.reorderEntries(series.id, [a.id, c.id, b.id]);
    await repository.updateEpisodeProgress(a.id, 1);
    expect((await repository.nextEntry(a.id))?.id, c.id);
    expect((await repository.listEntries(seriesId: series.id)).map((e) => e.id),
        [a.id, c.id, b.id]);
  });

  test('deleting a series keeps works independent unless explicitly removed',
      () async {
    final series = await repository.createSeries(
      const MediaSeriesDraft(title: '保留作品', category: MediaCategory.movie),
    );
    final entry = await repository.createEntry(MediaEntryDraft(
      title: '仍然存在',
      category: MediaCategory.movie,
      entryType: MediaEntryType.movie,
      seriesId: series.id,
    ));

    await repository.deleteSeries(series.id);
    expect((await repository.getEntry(entry.id))?.seriesId, isNull);

    final deleteSeries = await repository.createSeries(
      const MediaSeriesDraft(title: '一起删除', category: MediaCategory.tv),
    );
    final deleteEntry = await repository.createEntry(MediaEntryDraft(
      title: '删除作品',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      seriesId: deleteSeries.id,
    ));
    await repository.deleteSeries(deleteSeries.id, deleteEntries: true);
    expect(await repository.getEntry(deleteEntry.id), isNull);
  });
}
