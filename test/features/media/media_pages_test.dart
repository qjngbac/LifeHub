import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_entry_page.dart';
import 'package:lifehub/features/media/presentation/media_home_page.dart';
import 'package:lifehub/features/media/presentation/media_series_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('media home shows an honest empty state', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('影视进度'), findsOneWidget);
    expect(find.text('还没有影视记录'), findsOneWidget);
    expect(find.text('添加第一项'), findsOneWidget);
  });

  testWidgets('continue watching exposes the next episode', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '星河旅程',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      totalEpisodes: 12,
    ));
    await repository.updateEpisodeProgress(entry.id, 3);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('星河旅程'), findsOneWidget);
    expect(find.text('下一集：第 4 集'), findsOneWidget);
    expect(find.text('看完第 4 集'), findsOneWidget);
  });

  testWidgets('home counts empty series and works separately', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MediaRepository(database).createSeries(
      const MediaSeriesDraft(title: '空系列', category: MediaCategory.anime),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 个系列 · 0 项'), findsOneWidget);
  });

  testWidgets('status shortcuts open the combined filter page directly',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '正在追的剧',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 12,
    ));
    await repository.updateEpisodeProgress(entry.id, 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '在看 1'));
    await tester.pumpAndSettle();

    expect(find.text('全部分类'), findsOneWidget);
    expect(find.text('正在追的剧'), findsOneWidget);
  });

  testWidgets(
      'recent section excludes works already shown in continue watching',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final entry = await repository.createEntry(const MediaEntryDraft(
      title: '不要重复展示',
      category: MediaCategory.tv,
      entryType: MediaEntryType.season,
      totalEpisodes: 12,
    ));
    await repository.updateEpisodeProgress(entry.id, 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('不要重复展示'), findsOneWidget);
    expect(find.text('最近观看'), findsNothing);
  });

  testWidgets('media search stays inside the module', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await MediaRepository(database).createEntry(const MediaEntryDraft(
      title: '雪山纪录片',
      category: MediaCategory.movie,
      entryType: MediaEntryType.documentary,
      note: '冬季拍摄',
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), '雪山');
    await tester.pumpAndSettle();

    expect(find.text('模块内搜索结果'), findsOneWidget);
    expect(find.text('雪山纪录片'), findsOneWidget);
  });

  testWidgets('finishing a season suggests the next work', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final series = await repository.createSeries(
      const MediaSeriesDraft(title: '两季作品', category: MediaCategory.anime),
    );
    final first = await repository.createEntry(MediaEntryDraft(
      title: '第一季',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      totalEpisodes: 1,
    ));
    await repository.createEntry(MediaEntryDraft(
      title: '第二季',
      category: MediaCategory.anime,
      entryType: MediaEntryType.season,
      seriesId: series.id,
      totalEpisodes: 12,
    ));
    await repository.setStatus(first.id, MediaWatchStatus.watching);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('看完第 1 集'));
    await tester.pumpAndSettle();

    expect(find.text('已完成《第一季》；下一项：第二季'), findsOneWidget);
  });

  testWidgets('new work uses the last saved category and type', (tester) async {
    SharedPreferences.setMockInitialValues({
      'media_last_category': MediaCategory.anime.dbValue,
      'media_last_entry_type': MediaEntryType.ova.dbValue,
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: MediaHomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加第一项'));
    await tester.pumpAndSettle();

    final category = tester.widget<DropdownButtonFormField<MediaCategory>>(
      find.byType(DropdownButtonFormField<MediaCategory>),
    );
    final type = tester.widget<DropdownButtonFormField<MediaEntryType>>(
      find.byType(DropdownButtonFormField<MediaEntryType>),
    );
    expect(category.initialValue, MediaCategory.anime);
    expect(type.initialValue, MediaEntryType.ova);
  });

  testWidgets('entry detail has one combined status and progress card',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final entry = await MediaRepository(database).createEntry(
      const MediaEntryDraft(
        title: '一个详情',
        category: MediaCategory.tv,
        entryType: MediaEntryType.season,
      ),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: MediaEntryPage(entryId: entry.id)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('状态：想看'), findsOneWidget);
    expect(find.text('观看状态'), findsNothing);
    expect(find.text('修改进度'), findsOneWidget);
  });

  testWidgets('series reorder handles only appear in reorder mode',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final series = await repository.createSeries(
      const MediaSeriesDraft(title: '两部曲', category: MediaCategory.anime),
    );
    for (final title in ['第一项', '第二项']) {
      await repository.createEntry(MediaEntryDraft(
        title: title,
        category: MediaCategory.anime,
        entryType: MediaEntryType.season,
        seriesId: series.id,
      ));
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: MediaSeriesPage(seriesId: series.id)),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    await tester.tap(find.byTooltip('调整顺序'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
  });

  testWidgets('series page adds multiple seasons in one dialog',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = MediaRepository(database);
    final series = await repository.createSeries(const MediaSeriesDraft(
      title: '批量页面系列',
      category: MediaCategory.anime,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(home: MediaSeriesPage(seriesId: series.id)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('批量添加季'));
    await tester.pumpAndSettle();
    expect(find.text('批量添加季'), findsOneWidget);
    expect(find.byKey(const ValueKey('season-batch-title-0')), findsOneWidget);

    await tester.tap(find.text('添加一季'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('season-batch-title-1')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('season-batch-title-0')), '第1季');
    await tester.enterText(
        find.byKey(const ValueKey('season-batch-title-1')), '第2季');
    await tester.enterText(
        find.byKey(const ValueKey('season-batch-total-0')), '12');
    await tester.enterText(
        find.byKey(const ValueKey('season-batch-completed-0')), '12');
    await tester.enterText(
        find.byKey(const ValueKey('season-batch-total-1')), '24');
    await tester.enterText(
        find.byKey(const ValueKey('season-batch-completed-1')), '5');

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final entries = await repository.listEntries(seriesId: series.id);
    expect(entries.map((entry) => entry.title), ['第1季', '第2季']);
    expect(entries.map((entry) => entry.completedEpisodes), [12, 5]);
    expect(entries.map((entry) => entry.watchStatus), [
      MediaWatchStatus.completed.dbValue,
      MediaWatchStatus.watching.dbValue,
    ]);
  });
}
