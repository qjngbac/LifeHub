import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/credentials/data/credential_repository.dart';

void main() {
  late AppDatabase database;
  late CredentialRepository repository;
  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = CredentialRepository(database);
  });
  tearDown(() => database.close());

  test('stores only a user supplied number hint and calculates reminder date',
      () async {
    final record = await repository.create(CredentialDraft(
      name: '护照',
      numberHint: '尾号 1234',
      issuedDate: DateTime(2025, 1, 1),
      expiryDate: DateTime(2027, 1, 1),
      reminderDays: 60,
    ));
    expect(record.numberHint, '尾号 1234');
    expect(repository.reminderDate(record), DateTime(2026, 11, 2));
  });

  test('rejects reversed dates and negative reminder days', () async {
    expect(
      () => repository.create(CredentialDraft(
        name: '证件',
        issuedDate: DateTime(2027),
        expiryDate: DateTime(2026),
      )),
      throwsArgumentError,
    );
    expect(
      () => repository.create(const CredentialDraft(
        name: '证件',
        reminderDays: -2,
      )),
      throwsArgumentError,
    );
  });

  test('updates and soft deletes a credential', () async {
    final record = await repository.create(const CredentialDraft(name: '驾照'));
    final updated = await repository.update(
      record.id,
      CredentialDraft(
        name: '驾驶证',
        numberHint: '尾号 1239',
        expiryDate: DateTime(2028, 5, 2),
        reminderDays: 45,
      ),
    );
    expect(updated.name, '驾驶证');
    expect(updated.expiryDate, 20280502);
    await repository.delete(record.id);
    expect(await repository.list(), isEmpty);
  });
}
