import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/media/data/media_repository.dart';
import 'package:lifehub/features/media/domain/media_models.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/search/data/search_repository.dart';

void main() {
  for (final module in ['global', 'reading', 'library', 'media', 'parcel']) {
    test(
      'search audit $module treats slash percent and underscore literally',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        for (final title in ['100%完成', '1000完成', 'A_B', 'AXB', r'A\B', 'AB']) {
          await _insert(database, module, title);
        }
        for (final query in ['100%', 'A_B', r'A\B']) {
          final titles = await _search(database, module, query);
          expect(titles, [query == '100%' ? '100%完成' : query], reason: query);
        }
        expect(await _search(database, module, r'100\%'), isEmpty);
      },
    );
  }

  test(
    'search audit sensitive library record is local searchable but globally hidden',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final local = SavedItemRepository(database);
      final record = await local.create(
        const SavedItemDraft(
          title: '敏感私密便签',
          content: '本地检索内容',
          sensitive: true,
        ),
      );
      expect((await local.search('私密')).map((row) => row.id), [record.id]);
      expect((await local.search('本地检索')).map((row) => row.id), [record.id]);
      expect(await SearchRepository(database).search('私密'), isEmpty);
      expect(await SearchRepository(database).search('本地检索'), isEmpty);
      await local.archive(record.id);
      expect(await local.search('私密'), isEmpty);
    },
  );
}

Future<void> _insert(AppDatabase database, String module, String title) async {
  switch (module) {
    case 'global':
      await database
          .into(database.tasks)
          .insert(TasksCompanion.insert(title: title));
    case 'reading':
      await ReadingRepository(database).create(ReadingDraft(title: title));
    case 'library':
      await SavedItemRepository(database).create(SavedItemDraft(title: title));
    case 'media':
      await MediaRepository(database).createEntry(
        MediaEntryDraft(
          title: title,
          category: MediaCategory.movie,
          entryType: MediaEntryType.movie,
        ),
      );
    case 'parcel':
      await ParcelRepository(database).create(ParcelDraft(title: title));
  }
}

Future<List<String>> _search(
  AppDatabase database,
  String module,
  String query,
) async => switch (module) {
  'global' => (await SearchRepository(
    database,
  ).search(query)).map((row) => row.title).toList(),
  'reading' => (await ReadingRepository(
    database,
  ).search(query)).map((row) => row.title).toList(),
  'library' => (await SavedItemRepository(
    database,
  ).search(query)).map((row) => row.title).toList(),
  'media' => (await MediaRepository(
    database,
  ).search(query)).map((row) => row.title).toList(),
  'parcel' => (await ParcelRepository(
    database,
  ).search(query)).map((row) => row.title).toList(),
  _ => throw ArgumentError.value(module),
};
