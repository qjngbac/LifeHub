import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

void main() {
  test('exports clears restores and survives a database reopen', () async {
    final sandbox =
        await Directory.systemTemp.createTemp('lifehub-full-drill-');
    addTearDown(() => sandbox.delete(recursive: true));
    final backupFile = File('${sandbox.path}/preserved-backup.lhbk');
    final appStorage = Directory('${sandbox.path}/app-storage');
    final databaseFile = File('${appStorage.path}/lifehub.sqlite');
    final attachments = Directory('${appStorage.path}/attachments');
    await appStorage.create(recursive: true);

    var database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    final tasks = TaskRepository(database);
    await tasks.create(const TaskDraft(title: '完整演练任务'));
    await EventRepository(database).create(EventDraft(
      title: '完整演练日程',
      start: DateTime(2026, 8, 12, 9),
      end: DateTime(2026, 8, 12, 10),
    ));
    await database.into(database.savedItems).insert(
          SavedItemsCompanion.insert(
            id: const Value('full-drill-saved'),
            title: '完整演练资料',
          ),
        );
    final input = File('${sandbox.path}/input.txt');
    await input.writeAsString('完整演练附件内容');
    final attachmentRepository = AttachmentRepository(
      database,
      storageRoot: attachments,
    );
    final attachment = await attachmentRepository.importFile(input.path);
    await attachmentRepository.link(
      attachment.id,
      'SAVED_ITEM',
      'full-drill-saved',
    );

    final encrypted = await BackupService(
      database,
      attachmentStorageRoot: attachments,
    ).exportEncryptedJson(
      'full-drill-password',
      includeAttachmentFiles: true,
    );
    await backupFile.writeAsString(encrypted, flush: true);
    await database.close();

    await appStorage.delete(recursive: true);
    expect(await databaseFile.exists(), isFalse);
    expect(await attachments.exists(), isFalse);
    expect(await backupFile.exists(), isTrue);

    await appStorage.create(recursive: true);
    database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    await BackupService(database, attachmentStorageRoot: attachments)
        .importEncryptedJson(
      await backupFile.readAsString(),
      'full-drill-password',
    );
    await database.close();

    database = AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(database.close);
    expect(
        (await database.select(database.tasks).get()).single.title, '完整演练任务');
    expect(
        (await database.select(database.events).get()).single.title, '完整演练日程');
    expect((await database.select(database.savedItems).get()).single.title,
        '完整演练资料');
    final restored = (await database.select(database.attachments).get()).single;
    expect(await File(restored.storedPath).readAsString(), '完整演练附件内容');
    expect(await database.select(database.attachmentLinks).get(), hasLength(1));
  });
}
