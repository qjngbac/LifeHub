import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/life_event_repository.dart';

void main() {
  late AppDatabase database;
  late LifeEventRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = LifeEventRepository(database);
  });
  tearDown(() => database.close());

  test('daily events are queried by local date and relationship context',
      () async {
    await repository.create(LifeEventDraft(
      title: '完成了第一版',
      date: DateTime(2026, 8, 9),
      timeMinutes: 18 * 60 + 30,
    ));
    await repository.create(LifeEventDraft(
      title: '一起散步',
      date: DateTime(2026, 8, 9),
      relationshipId: 'relation-1',
    ));
    await repository.create(LifeEventDraft(
      title: '明天的记录',
      date: DateTime(2026, 8, 10),
    ));

    expect(
      (await repository.forDate(DateTime(2026, 8, 9)))
          .map((entry) => entry.title),
      ['完成了第一版'],
    );
    expect(
      (await repository.forDate(DateTime(2026, 8, 9),
              relationshipId: 'relation-1'))
          .single
          .title,
      '一起散步',
    );
  });

  test('daily event rejects invalid clock minutes', () {
    expect(
      () => repository.create(LifeEventDraft(
        title: '错误时间',
        date: DateTime(2026, 8, 9),
        timeMinutes: 1440,
      )),
      throwsArgumentError,
    );
  });
}
