import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/cycle_repository.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';

void main() {
  late AppDatabase database;
  late CycleRepository repository;
  late String relationshipId;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    relationshipId = (await RelationshipRepository(database).create(
      RelationshipDraft(name: '小岚', startDate: DateTime(2025, 2, 14)),
    ))
        .id;
    repository = CycleRepository(database);
  });
  tearDown(() => database.close());

  test('manual cycle range marks every inclusive local date', () async {
    final record = await repository.create(CycleDraft(
      relationshipId: relationshipId,
      start: DateTime(2026, 8, 3),
      end: DateTime(2026, 8, 7),
    ));

    expect(repository.containsDate(record, DateTime(2026, 8, 3)), isTrue);
    expect(repository.containsDate(record, DateTime(2026, 8, 7)), isTrue);
    expect(repository.containsDate(record, DateTime(2026, 8, 8)), isFalse);
    expect(await repository.forMonth(relationshipId, DateTime(2026, 8)),
        hasLength(1));
  });

  test('cycle end cannot be before start and relationship must exist', () {
    expect(
      () => repository.create(CycleDraft(
        relationshipId: relationshipId,
        start: DateTime(2026, 8, 8),
        end: DateTime(2026, 8, 7),
      )),
      throwsArgumentError,
    );
    expect(
      () => repository.create(CycleDraft(
        relationshipId: 'missing',
        start: DateTime(2026, 8, 8),
      )),
      throwsA(isA<StateError>()),
    );
  });
}
