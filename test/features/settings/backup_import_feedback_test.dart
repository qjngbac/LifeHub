import 'dart:io';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/settings/presentation/my_page.dart';
import 'package:lifehub/features/task/data/task_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Picker extends FilePicker {
  _Picker(this.file);
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
  }) async => FilePickerResult([
    PlatformFile(
      name: 'backup.json',
      path: file.path,
      size: await file.length(),
    ),
  ]);
}

class _Directories extends PathProviderPlatform {
  _Directories(this.directory);
  final Directory directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  for (final restore in [false, true]) {
    testWidgets(
      '${restore ? "restore" : "import"} reports committed data when reminder refresh fails',
      (tester) async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        final source = AppDatabase.forTesting(NativeDatabase.memory());
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('backup-feedback-'),
        ))!;
        addTearDown(database.close);
        addTearDown(source.close);
        addTearDown(() => directory.delete(recursive: true));
        final previousDirectories = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Directories(directory);
        addTearDown(() => PathProviderPlatform.instance = previousDirectories);
        final file = (await tester.runAsync(() async {
          await TaskRepository(source).create(const TaskDraft(title: '导入的任务'));
          final backupDirectory = Directory(
            '${directory.path}/lifehub_backups',
          );
          await backupDirectory.create();
          final file = File('${backupDirectory.path}/backup.json');
          await file.writeAsString(await BackupService(source).exportJson());
          return file;
        }))!;
        FilePicker.platform = _Picker(file);
        addTearDown(() => FilePicker.platform = FilePickerIO());
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'REMINDER_REFRESH_FAILED');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(database)],
            child: const MaterialApp(home: MyPage()),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.widgetWithText(
          ListTile,
          restore ? '恢复最近备份' : '导入 JSON 备份',
        );
        await tester.scrollUntilVisible(
          action,
          250,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 8,
        );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle(const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 1));
        final confirm = restore
            ? find.widgetWithText(FilledButton, '确认恢复')
            : find.widgetWithText(TextButton, '合并导入');
        await tester.runAsync(() => tester.tap(action));
        await _pumpIOUntil(tester, confirm);
        await tester.runAsync(() => tester.tap(confirm));
        await _pumpIOUntil(tester, find.byType(SnackBar));

        expect(
          (await database.select(database.tasks).get()).single.title,
          '导入的任务',
        );
        expect(find.textContaining('提醒刷新失败'), findsOneWidget);
        expect(find.textContaining('未被修改'), findsNothing);
      },
    );
  }
}

Future<void> _pumpIOUntil(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (target.evaluate().isNotEmpty) return;
  }
  expect(target, findsOneWidget);
}
