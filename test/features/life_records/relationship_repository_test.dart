import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/life_records/data/relationship_repository.dart';

void main() {
  late AppDatabase database;
  late RelationshipRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RelationshipRepository(database);
  });
  tearDown(() => database.close());

  test('relationship profile can be created updated and archived', () async {
    final created = await repository.create(RelationshipDraft(
      name: ' 小岚 ',
      nickname: '对象',
      startDate: DateTime(2025, 2, 14),
      birthday: DateTime(2002, 6, 8),
    ));
    expect(created.name, '小岚');
    expect(created.startDate, 20250214);

    final updated = await repository.update(
      created.id,
      RelationshipDraft(
        name: '小岚',
        nickname: '爱人',
        startDate: DateTime(2025, 2, 14),
      ),
    );
    expect(updated.nickname, '爱人');

    await repository.archive(created.id);
    expect(await repository.list(), isEmpty);
    expect(
        (await repository.list(includeArchived: true)).single.active, isFalse);
  });
}
