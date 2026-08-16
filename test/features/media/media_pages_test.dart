import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/media/presentation/media_home_page.dart';

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
    expect(find.text('添加第一部'), findsOneWidget);
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
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('已完成《第一季》；下一部：第二季'), findsOneWidget);
  });
}
