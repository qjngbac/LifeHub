import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/event/data/event_repository.dart';

void main() {
  late AppDatabase database;
  late EventRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = EventRepository(database);
  });

  tearDown(() => database.close());

  test('window query includes overlapping event and excludes later event',
      () async {
    await repository.create(
      EventDraft(
        title: '上午会议',
        start: DateTime.utc(2026, 8, 8, 9),
        end: DateTime.utc(2026, 8, 8, 10),
      ),
    );
    await repository.create(
      EventDraft(
        title: '明天会议',
        start: DateTime.utc(2026, 8, 9, 9),
        end: DateTime.utc(2026, 8, 9, 10),
      ),
    );

    final events = await repository.listWindow(
      DateTime.utc(2026, 8, 8),
      DateTime.utc(2026, 8, 9),
    );

    expect(events.map((event) => event.title), ['上午会议']);
  });

  test('event rejects an end before its start', () async {
    expect(
      () => repository.create(
        EventDraft(
          title: '错误日程',
          start: DateTime.utc(2026, 8, 8, 10),
          end: DateTime.utc(2026, 8, 8, 9),
        ),
      ),
      throwsArgumentError,
    );
  });
  test('recurring events expand inside a later visible window', () async {
    await repository.create(EventDraft(
      title: '每周例会',
      start: DateTime(2026, 8, 3, 9),
      end: DateTime(2026, 8, 3, 10),
      repeatRule: 'FREQ=WEEKLY;INTERVAL=1',
    ));

    final occurrences = await repository.occurrencesWindow(
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 11),
    );
    expect(occurrences, hasLength(1));
    expect(occurrences.single.start.day, 10);
  });

  test('all-day occurrence uses stable local date and can be updated/archived',
      () async {
    final event = await repository.create(EventDraft(
      title: 'all day',
      start: DateTime(2026, 8, 9),
      end: DateTime(2026, 8, 10),
      allDay: true,
      localDate: 20260808,
    ));

    final occurrences = await repository.occurrencesWindow(
      DateTime(2026, 8, 8),
      DateTime(2026, 8, 9),
    );
    expect(occurrences.single.start, DateTime(2026, 8, 8));

    final updated = await repository.update(
      event.id,
      EventDraft(
        title: 'updated',
        start: DateTime(2026, 8, 8),
        end: DateTime(2026, 8, 9),
        allDay: true,
        localDate: 20260808,
      ),
    );
    expect(updated.title, 'updated');
    await repository.archive(event.id);
    expect(
      await repository.occurrencesWindow(
        DateTime(2026, 8, 8),
        DateTime(2026, 8, 9),
      ),
      isEmpty,
    );
  });

  test('archived events restore and deleted events remain recoverable',
      () async {
    final archived = await repository.create(EventDraft(
      title: '保留归档',
      start: DateTime(2026, 8, 8, 9),
      end: DateTime(2026, 8, 8, 10),
    ));
    final deleted = await repository.create(EventDraft(
      title: '彻底删除',
      start: DateTime(2026, 8, 8, 11),
      end: DateTime(2026, 8, 8, 12),
    ));

    await repository.archive(archived.id);
    await repository.delete(deleted.id);

    expect(
      (await repository.listArchived()).map((event) => event.title),
      ['保留归档'],
    );
    await repository.restore(archived.id);
    expect(await repository.listArchived(), isEmpty);
    expect(await repository.get(archived.id), isNotNull);
    expect((await repository.get(deleted.id)).deletedAt, isNotNull);
    final visible = await repository.listWindow(
      DateTime(2026, 8, 8),
      DateTime(2026, 8, 9),
    );
    expect(visible.map((event) => event.title), ['保留归档']);
  });
}
