import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/mood_repository.dart';
import 'package:lifehub/features/life_records/domain/mood_catalog.dart';

void main() {
  late AppDatabase database;
  late MoodRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MoodRepository(database);
  });
  tearDown(() => database.close());

  test('one context has one primary mood per date and upsert keeps its id',
      () async {
    final first = await repository.save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.happy,
      intensity: 4,
    ));
    final updated = await repository.save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.angry,
      intensity: 2,
      note: '沟通不顺',
    ));

    expect(updated.id, first.id);
    expect(updated.moodCode, MoodCatalog.angry);
    expect(updated.note, '沟通不顺');
    expect(await repository.forMonth(DateTime(2026, 8)), hasLength(1));
  });

  test('self and relationship moods on the same day stay isolated', () async {
    await repository.save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.calm,
    ));
    await repository.save(MoodDraft(
      date: DateTime(2026, 8, 9),
      moodCode: MoodCatalog.sad,
      relationshipId: 'relation-1',
    ));

    expect((await repository.forDate(DateTime(2026, 8, 9)))!.moodCode,
        MoodCatalog.calm);
    expect(
      (await repository.forDate(DateTime(2026, 8, 9),
              relationshipId: 'relation-1'))!
          .moodCode,
      MoodCatalog.sad,
    );
    expect(MoodCatalog.emoji(MoodCatalog.angry), '😠');
    expect(MoodCatalog.label(MoodCatalog.calm), '平静');
  });

  test('mood rejects unknown codes and intensity outside one to five', () {
    expect(
      () => repository.save(MoodDraft(
        date: DateTime(2026, 8, 9),
        moodCode: 'UNKNOWN',
      )),
      throwsArgumentError,
    );
    expect(
      () => repository.save(MoodDraft(
        date: DateTime(2026, 8, 9),
        moodCode: MoodCatalog.happy,
        intensity: 6,
      )),
      throwsArgumentError,
    );
  });
}
