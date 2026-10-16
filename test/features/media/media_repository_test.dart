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

  test('creates multiple seasons with independent progress in one batch',
      () async {
    final series = await repository.createSeries(const MediaSeriesDraft(
      title: '批量添加系列',
      category: MediaCategory.anime,
    ));

    final entries = await repository.createEntries([
      MediaEntryDraft(
        title: '第1季',
        category: MediaCategory.anime,
        entryType: MediaEntryType.season,
        seriesId: series.id,
        totalEpisodes: 12,
        completedEpisodes: 12,
      ),
      MediaEntryDraft(
        title: '第2季',
        category: MediaCategory.anime,
        entryType: MediaEntryType.season,
        seriesId: series.id,
        totalEpisodes: 24,
        completedEpisodes: 5,
      ),
      MediaEntryDraft(
        title: '第3季',
        category: MediaCategory.anime,
        entryType: MediaEntryType.season,
        seriesId: series.id,
        totalEpisodes: 10,
      ),
    ]);

    expect(entries.map((entry) => entry.title), ['第1季', '第2季', '第3季']);
    expect(entries.map((entry) => entry.totalEpisodes), [12, 24, 10]);
    expect(entries.map((entry) => entry.completedEpisodes), [12, 5, 0]);
    expect(entries.map((entry) => entry.watchStatus), [
      MediaWatchStatus.completed.dbValue,
      MediaWatchStatus.watching.dbValue,
      MediaWatchStatus.plan.dbValue,
    ]);
  });

  test('batch season creation is atomic when one progress is invalid',
      () async {
    final series = await repository.createSeries(const MediaSeriesDraft(
      title: '批量校验系列',
      category: MediaCategory.anime,
    ));

    expect(
      () => repository.createEntries([
        MediaEntryDraft(
          title: '第1季',
          category: MediaCategory.anime,
          entryType: MediaEntryType.season,
          seriesId: series.id,
          totalEpisodes: 12,
          completedEpisodes: 3,
        ),
        MediaEntryDraft(
          title: '第2季',
          category: MediaCategory.anime,
          entryType: MediaEntryType.season,
          seriesId: series.id,
          totalEpisodes: 8,
          completedEpisodes: 9,
        ),
      ]),
      throwsRangeError,
    );

    expect(await repository.listEntries(seriesId: series.id), isEmpty);
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

  test('correcting episode progress keeps the real last watched time',
      () async {
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '进度纠错',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 12,
    ));
    final watchedAt = DateTime.utc(2026, 8, 12, 20);
    final correctedAt = DateTime.utc(2026, 8, 13, 9);

    await repository.updateEpisodeProgress(entry.id, 5, now: watchedAt);
    final corrected = await repository.updateEpisodeProgress(
      entry.id,
      4,
      now: correctedAt,
    );

    expect(corrected.completedEpisodes, 4);
    expect(corrected.lastWatchedAt, watchedAt.millisecondsSinceEpoch);
  });

  test('completed status fills known progress and records viewing activity',
      () async {
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '直接完成',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      totalEpisodes: 12,
      completedEpisodes: 3,
      watchStatus: MediaWatchStatus.watching,
    ));

    final completed =
        await repository.setStatus(entry.id, MediaWatchStatus.completed);

    expect(completed.completedEpisodes, 12);
    expect(completed.watchStatus, MediaWatchStatus.completed.dbValue);
    expect(completed.lastWatchedAt, isNotNull);
    expect(completed.completedAt, isNotNull);
  });

  test('saved progress cannot remain in the plan status', () async {
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '已有进度',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 10,
      completedEpisodes: 2,
    ));

    expect(entry.watchStatus, MediaWatchStatus.watching.dbValue);
  });

  test('resetting progress returns an active work to the plan status',
      () async {
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '重置进度',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 10,
    ));
    await repository.updateEpisodeProgress(entry.id, 2);

    final reset = await repository.updateEpisodeProgress(entry.id, 0);

    expect(reset.completedEpisodes, 0);
    expect(reset.watchStatus, MediaWatchStatus.plan.dbValue);
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

  test('a soft-deleted work can be restored from an undo action', () async {
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '可撤销删除',
      category: MediaCategory.movie,
      entryType: MediaEntryType.movie,
    ));

    await repository.deleteEntry(entry.id);
    expect(await repository.getEntry(entry.id), isNull);

    await repository.restoreEntry(entry.id);
    expect((await repository.getEntry(entry.id))?.title, '可撤销删除');
  });
}
