import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/attachment/data/attachment_storage.dart';

void main() {
  late AppDatabase database;
  late Directory temporary;
  late AttachmentRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    temporary = await Directory.systemTemp.createTemp('lifehub-attachment-');
    repository = AttachmentRepository(database, storageRoot: temporary);
  });
  tearDown(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test('copies files, reuses duplicate content and deduplicates links',
      () async {
    final source = File('${temporary.path}/source.txt');
    await source.writeAsString('LifeHub attachment');
    final first = await repository.importFile(source.path);
    final duplicate = await repository.importFile(source.path);
    expect(duplicate.id, first.id);
    expect(File(first.storedPath).existsSync(), isTrue);

    await repository.link(first.id, 'TRIP', 'trip-1');
    await repository.link(first.id, 'TRIP', 'trip-1');
    expect(await repository.forEntity('TRIP', 'trip-1'), hasLength(1));
  });

  test('rejects a missing source file', () async {
    expect(
      () => repository.importFile('${temporary.path}/missing.txt'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects an attachment larger than the local safety limit', () async {
    final source = File('${temporary.path}/oversized.bin');
    await source.open(mode: FileMode.write).then((handle) async {
      await handle.truncate(25 * 1024 * 1024 + 1);
      await handle.close();
    });

    await expectLater(
      repository.importFile(source.path),
      throwsArgumentError,
    );
    expect(await database.select(database.attachments).get(), isEmpty);
  });

  test('unlink and delete orphan removes its private file', () async {
    final source = File('${temporary.path}/photo.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final attachment = await repository.importFile(source.path);
    await repository.link(attachment.id, 'SAVED_ITEM', 'note-1');

    await repository.unlinkAndDeleteOrphan(
      attachment.id,
      'SAVED_ITEM',
      'note-1',
    );

    expect(File(attachment.storedPath).existsSync(), isFalse);
    expect(await repository.forEntity('SAVED_ITEM', 'note-1'), isEmpty);
  });

  test('legacy app_flutter attachments migrate into FileProvider files storage',
      () async {
    final legacyBase =
        await Directory.systemTemp.createTemp('lifehub-legacy-files-');
    final filesBase =
        await Directory.systemTemp.createTemp('lifehub-provider-files-');
    addTearDown(() => legacyBase.delete(recursive: true));
    addTearDown(() => filesBase.delete(recursive: true));
    final source = File('${temporary.path}/legacy-note.txt');
    await source.writeAsString('legacy attachment');
    final legacy = await AttachmentRepository(
      database,
      storageRoot: legacyBase,
    ).importFile(source.path);

    final migrated = await AttachmentStorage.migrateLegacyFiles(
      database,
      filesBase: filesBase,
      legacyBase: legacyBase,
    );

    final restored = await repository.get(legacy.id);
    expect(migrated, 1);
    expect(restored.storedPath, startsWith(filesBase.path));
    expect(await File(restored.storedPath).readAsString(), 'legacy attachment');
    expect(await File(legacy.storedPath).exists(), isFalse);
  });
}
