import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';

void main() {
  late AppDatabase database;
  late AnniversaryRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AnniversaryRepository(database);
  });
  tearDown(() => database.close());

  test('annual anniversary calculates its next date and remaining days',
      () async {
    final anniversary = await repository.create(AnniversaryDraft(
      title: '在一起纪念日',
      date: DateTime(2024, 8, 20),
      repeatYearly: true,
      category: 'RELATIONSHIP',
    ));

    expect(
      repository.nextOccurrence(anniversary, DateTime(2026, 8, 9)),
      DateTime(2026, 8, 20),
    );
    expect(repository.daysUntil(anniversary, DateTime(2026, 8, 9)), 11);
  });

  test('february 29 anniversary falls on february 28 in non-leap years',
      () async {
    final anniversary = await repository.create(AnniversaryDraft(
      title: '特别日期',
      date: DateTime(2024, 2, 29),
      repeatYearly: true,
    ));
    expect(
      repository.nextOccurrence(anniversary, DateTime(2025, 1, 1)),
      DateTime(2025, 2, 28),
    );
  });

  test('non-repeating past date remains past', () async {
    final anniversary = await repository.create(AnniversaryDraft(
      title: '考试',
      date: DateTime(2026, 8, 1),
      repeatYearly: false,
    ));
    expect(repository.daysUntil(anniversary, DateTime(2026, 8, 9)), -8);
  });
}
