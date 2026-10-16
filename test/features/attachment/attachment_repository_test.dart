import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/attachment/data/attachment_storage.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';

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

  test('unlinking one of three shared entities preserves the other two',
      () async {
    final source = File('${temporary.path}/shared.txt');
    await source.writeAsString('shared content');
    final attachment = await repository.importFile(source.path);
    for (final id in ['first', 'second', 'third']) {
      await repository.link(attachment.id, 'SAVED_ITEM', id);
    }

    expect(
        await repository.unlinkAndDeleteOrphan(
          attachment.id,
          'SAVED_ITEM',
          'first',
        ),
        isFalse);

    expect(await repository.forEntity('SAVED_ITEM', 'first'), isEmpty);
    expect(await repository.forEntity('SAVED_ITEM', 'second'), hasLength(1));
    expect(await repository.forEntity('SAVED_ITEM', 'third'), hasLength(1));
    expect(await File(attachment.storedPath).readAsString(), 'shared content');
  });

  test('deleting the last attachment link leaves a restorable backup',
      () async {
    final savedItems = SavedItemRepository(database);
    final removedItem = await savedItems.create(
      const SavedItemDraft(title: 'remove attachment'),
    );
    final retainedItem = await savedItems.create(
      const SavedItemDraft(title: 'keep attachment'),
    );
    final source = File('${temporary.path}/removed.txt');
    await source.writeAsString('removed content');
    final removed = await repository.importFile(source.path);
    await repository.link(removed.id, 'SAVED_ITEM', removedItem.id);
    final retainedSource = File('${temporary.path}/retained.txt');
    await retainedSource.writeAsString('retained content');
    final retained = await repository.importFile(retainedSource.path);
    await repository.link(retained.id, 'SAVED_ITEM', retainedItem.id);

    expect(
        await repository.unlinkAndDeleteOrphan(
          removed.id,
          'SAVED_ITEM',
          removedItem.id,
        ),
        isTrue);
    final links = await database.select(database.attachmentLinks).get();
    expect(links.map((row) => row.attachmentId), [retained.id]);
    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    await BackupService(
      restored,
      attachmentStorageRoot: Directory('${temporary.path}/restored'),
    ).importJson(await BackupService(database).exportJson());

    expect(await File(removed.storedPath).exists(), isFalse);
    final restoredAttachment =
        (await restored.select(restored.attachments).get()).single;
    expect(restoredAttachment.id, retained.id);
    expect(await File(restoredAttachment.storedPath).readAsString(),
        'retained content');
    expect(await restored.select(restored.savedItems).get(), hasLength(2));
  });

  test('orphan cleanup preserves shared files and removes stale links',
      () async {
    final source = File('${temporary.path}/shared.txt');
    await source.writeAsString('shared content');
    final shared = await repository.importFile(source.path);
    await repository.link(shared.id, 'SAVED_ITEM', 'first');
    await repository.link(shared.id, 'SAVED_ITEM', 'second');
    final orphanSource = File('${temporary.path}/orphan.txt');
    await orphanSource.writeAsString('orphan content');
    final orphan = await repository.importFile(orphanSource.path);
    await repository.link(orphan.id, 'SAVED_ITEM', 'old');
    await repository.unlink(orphan.id, 'SAVED_ITEM', 'old');

    expect(await repository.deleteOrphans(), 1);

    expect(await File(shared.storedPath).readAsString(), 'shared content');
    expect(await File(orphan.storedPath).exists(), isFalse);
    expect((await database.select(database.attachments).get()).single.id,
        shared.id);
    expect(
        (await database.select(database.attachmentLinks).get())
            .map((row) => row.attachmentId)
            .toSet(),
        {shared.id});
  });

  test('failed attachment deletion preserves the link and physical file',
      () async {
    final source = File('${temporary.path}/protected.txt');
    await source.writeAsString('must survive rollback');
    final attachment = await repository.importFile(source.path);
    await repository.link(attachment.id, 'SAVED_ITEM', 'first');
    await database.customStatement(
      "CREATE TRIGGER reject_attachment_delete BEFORE DELETE ON attachments "
      "BEGIN SELECT RAISE(ABORT, 'test deletion failure'); END",
    );

    await expectLater(
        repository.unlinkAndDeleteOrphan(
          attachment.id,
          'SAVED_ITEM',
          'first',
        ),
        throwsA(anything));

    expect(await File(attachment.storedPath).readAsString(),
        'must survive rollback');
    expect(await repository.forEntity('SAVED_ITEM', 'first'), hasLength(1));
  });
}
