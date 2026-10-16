import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/backup/encrypted_backup_codec.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/features/task/data/task_repository.dart';

class _AfterTasksRead extends QueryInterceptor {
  Future<void> Function()? action;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement == 'SELECT * FROM "tasks";' && action != null) {
      final callback = action!;
      action = null;
      await callback();
    }
    return rows;
  }
}

class _FilePicker extends FilePicker {
  _FilePicker(this.file);
  final File file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
            name: file.uri.pathSegments.last,
            size: await file.length(),
            path: file.path),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => FilePicker.platform = _FilePicker(File('unused')));

  test('export keeps a database snapshot while another connection writes',
      () async {
    final root = await Directory.systemTemp.createTemp('lifehub-snapshot-');
    final file = File('${root.path}/database.sqlite');
    final interceptor = _AfterTasksRead();
    final source = AppDatabase.forTesting(
      NativeDatabase(file,
              setup: (db) => db.execute('PRAGMA journal_mode = WAL'))
          .interceptWith(interceptor),
    );
    final writer = AppDatabase.forTesting(NativeDatabase(file));
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await source.close();
      await writer.close();
      await target.close();
      await root.delete(recursive: true);
    });
    await source.into(source.projects).insert(
          ProjectsCompanion.insert(id: const Value('project'), name: 'Project'),
        );
    await TaskRepository(source)
        .create(const TaskDraft(title: 'Task', projectId: 'project'));
    await writer.customSelect('SELECT 1').get();
    var interleaved = false;
    var blocked = false;
    Future<void> removeProject() => writer.transaction(() async {
          await writer.delete(writer.tasks).go();
          await writer.delete(writer.projects).go();
        });
    interceptor.action = () async {
      try {
        await removeProject();
      } catch (error) {
        expect(error.toString(), contains('database is locked'));
        blocked = true;
      }
      interleaved = true;
    };
    final backup = await BackupService(source).exportJson();
    expect(interleaved, isTrue);
    expect(blocked, isTrue);
    await removeProject();
    await BackupService(target).importJson(backup);
    expect(await target.select(target.tasks).get(), hasLength(1));
    expect(await target.select(target.projects).get(), hasLength(1));
    expect(await writer.select(writer.projects).get(), isEmpty);
  });

  test('full export rejects attachment bytes changed after import', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('lifehub-digest-');
    addTearDown(() async {
      await source.close();
      await root.delete(recursive: true);
    });
    final file =
        await File('${root.path}/original.txt').writeAsString('original');
    final attachment = await AttachmentRepository(source, storageRoot: root)
        .importFile(file.path);
    await File(attachment.storedPath).writeAsString('modified');
    await expectLater(
        BackupService(source).exportJson(), throwsFormatException);
    expect(
        await BackupService(source).exportJson(includeAttachmentFiles: false),
        isNotEmpty);
  });

  test('export omits legacy deleted links to physically removed attachments',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    await source.into(source.attachmentLinks).insert(
          AttachmentLinksCompanion.insert(
            attachmentId: 'removed',
            entityType: 'TASK',
            entityId: 'removed-task',
            deletedAt: const Value(1),
          ),
        );
    await BackupService(target)
        .importJson(await BackupService(source).exportJson());
    expect(await target.select(target.attachmentLinks).get(), isEmpty);
    expect(await source.select(source.attachmentLinks).get(), hasLength(1));
  });

  test('recurring task lineage survives backup and restore', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);
    final task = await TaskRepository(source).create(TaskDraft(
      title: 'Daily task',
      dueAt: DateTime.utc(2026, 10, 4),
      repeatRule: 'FREQ=DAILY',
    ));
    await TaskRepository(source).setStatus(task.id, TaskStatus.done);
    await BackupService(target)
        .importJson(await BackupService(source).exportJson());
    await TaskRepository(target).setStatus(task.id, TaskStatus.todo);
    await TaskRepository(target).setStatus(task.id, TaskStatus.done);
    expect(await target.select(target.tasks).get(), hasLength(2));
  });

  test('full export reports a missing attachment instead of silently losing it',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('lifehub-missing-file-');
    addTearDown(() async {
      await source.close();
      await root.delete(recursive: true);
    });
    final file =
        await File('${root.path}/original.txt').writeAsString('original');
    final attachment = await AttachmentRepository(source, storageRoot: root)
        .importFile(file.path);
    await File(attachment.storedPath).delete();
    await expectLater(
        BackupService(source).exportJson(), throwsFormatException);
    expect(
        await BackupService(source).exportJson(includeAttachmentFiles: false),
        isNotEmpty);
  });

  test('encrypted backup above 64 MiB can be picked, decrypted and restored',
      () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    final root =
        await Directory.systemTemp.createTemp('lifehub-large-encrypted-');
    final originalPicker = FilePicker.platform;
    addTearDown(() async {
      FilePicker.platform = originalPicker;
      await source.close();
      await target.close();
      await root.delete(recursive: true);
    });
    final repository = AttachmentRepository(source,
        storageRoot: Directory('${root.path}/input'));
    final bytes = Uint8List(20 * 1024 * 1024);
    for (var index = 0; index < 2; index++) {
      bytes[0] = index;
      final input = await File('${root.path}/$index.bin').writeAsBytes(bytes);
      await repository.importFile(input.path);
    }
    final codec =
        EncryptedBackupCodec(memoryKiB: 1024, iterations: 1, parallelism: 1);
    final encrypted = await BackupService(source)
        .exportEncryptedJson('strong-password', codec: codec);
    final file =
        await File('${root.path}/backup.lifehubx').writeAsString(encrypted);
    expect(await file.length(), greaterThan(BackupService.maxImportBytes));
    FilePicker.platform = _FilePicker(file);
    final picked = await BackupService(target).pickBackupText();
    await BackupService(target,
            attachmentStorageRoot: Directory('${root.path}/restored'))
        .importEncryptedJson(picked!, 'strong-password', codec: codec);
    final restored = await target.select(target.attachments).get();
    expect(restored, hasLength(2));
    for (final attachment in restored) {
      expect(
          AttachmentRepository.contentDigest(
              await File(attachment.storedPath).readAsBytes()),
          attachment.contentDigest);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('plain and mixed pickers still reject oversized plain files', () async {
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('lifehub-plain-limit-');
    final originalPicker = FilePicker.platform;
    addTearDown(() async {
      FilePicker.platform = originalPicker;
      await source.close();
      await root.delete(recursive: true);
    });
    final file = File('${root.path}/large.json');
    final handle = await file.open(mode: FileMode.write);
    await handle.writeString('{}');
    await handle.truncate(BackupService.maxImportBytes + 1);
    await handle.close();
    FilePicker.platform = _FilePicker(file);
    await expectLater(
        BackupService(source).pickBackupJson(), throwsFormatException);
    await expectLater(
        BackupService(source).pickBackupText(), throwsFormatException);
  });
}
