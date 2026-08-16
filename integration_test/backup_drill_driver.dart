import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/event/data/event_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:path_provider/path_provider.dart';

const _phase = String.fromEnvironment('DRILL_PHASE', defaultValue: 'export');
const _password = 'LifeHub-Stability-Only-2026';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('backup clear restore drill $_phase', (tester) async {
    final database = AppDatabase();
    addTearDown(database.close);
    final documents = await getApplicationDocumentsDirectory();
    final files = Directory('${documents.parent.path}/files');
    await files.create(recursive: true);
    final backupFile = File('${files.path}/lifehub_stability_backup.lhbk');
    final attachmentRoot = Directory('${documents.path}/lifehub_attachments');
    final backup = BackupService(
      database,
      attachmentStorageRoot: attachmentRoot,
    );

    if (_phase == 'export') {
      await _seed(database, files, attachmentRoot);
      final encoded = await backup.exportEncryptedJson(
        _password,
        includeAttachmentFiles: true,
      );
      await backupFile.writeAsString(encoded, flush: true);
      expect(await database.select(database.tasks).get(), hasLength(2));
      expect(await database.select(database.events).get(), hasLength(1));
      expect(await database.select(database.savedItems).get(), hasLength(1));
      expect(await database.select(database.attachments).get(), hasLength(1));
      expect(await backupFile.length(), greaterThan(100));
    } else if (_phase == 'import') {
      expect(await backupFile.exists(), isTrue);
      await backup.importEncryptedJson(
        await backupFile.readAsString(),
        _password,
      );
      expect(
        (await database.select(database.tasks).get()).map((row) => row.title),
        containsAll(['演练任务一', '演练任务二']),
      );
      expect(
        (await database.select(database.events).get()).single.title,
        '演练日程',
      );
      expect(
        (await database.select(database.savedItems).get()).single.title,
        '演练资料',
      );
      final attachment =
          (await database.select(database.attachments).get()).single;
      expect(await File(attachment.storedPath).readAsString(), '演练附件内容');
    } else {
      fail('Unknown DRILL_PHASE=$_phase');
    }
  });
}

Future<void> _seed(
  AppDatabase database,
  Directory files,
  Directory attachmentRoot,
) async {
  final tasks = TaskRepository(database);
  await tasks.create(const TaskDraft(title: '演练任务一'));
  await tasks.create(TaskDraft(
    title: '演练任务二',
    dueAt: DateTime(2026, 8, 12, 20),
  ));
  await EventRepository(database).create(EventDraft(
    title: '演练日程',
    start: DateTime(2026, 8, 12, 9),
    end: DateTime(2026, 8, 12, 10),
  ));
  await database.into(database.savedItems).insert(
        SavedItemsCompanion.insert(
          id: const Value('stability-saved-item'),
          title: '演练资料',
          content: const Value('用于验证清空后的恢复结果'),
        ),
      );
  final input = File('${files.path}/lifehub_stability_attachment.txt');
  await input.writeAsString('演练附件内容', flush: true);
  final attachments = AttachmentRepository(
    database,
    storageRoot: attachmentRoot,
  );
  final attachment = await attachments.importFile(input.path);
  await attachments.link(
    attachment.id,
    'SAVED_ITEM',
    'stability-saved-item',
  );
}
