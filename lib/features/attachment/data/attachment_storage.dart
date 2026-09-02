import 'dart:io';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract final class AttachmentStorage {
  static const directoryName = 'lifehub_attachments';

  static Future<Directory> applicationDirectory() async => Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          directoryName,
        ),
      );

  static Future<int> migrateLegacyFiles(
    AppDatabase database, {
    Directory? filesBase,
    Directory? legacyBase,
  }) async {
    final currentBase = filesBase ?? await getApplicationSupportDirectory();
    final oldBase = legacyBase ?? await getApplicationDocumentsDirectory();
    final targetRoot = Directory(p.join(currentBase.path, directoryName));
    final legacyRoot = Directory(p.join(oldBase.path, directoryName));
    if (p.equals(targetRoot.absolute.path, legacyRoot.absolute.path) ||
        !await legacyRoot.exists()) {
      return 0;
    }
    await targetRoot.create(recursive: true);
    final attachments = await database.select(database.attachments).get();
    var migrated = 0;
    for (final attachment in attachments) {
      final source = File(attachment.storedPath);
      final sourcePath = source.absolute.path;
      if (!p.isWithin(legacyRoot.absolute.path, sourcePath) ||
          !await source.exists()) {
        continue;
      }
      final target = File(p.join(targetRoot.path, p.basename(source.path)));
      if (!await target.exists()) await source.copy(target.path);
      await (database.update(database.attachments)
            ..where((row) => row.id.equals(attachment.id)))
          .write(AttachmentsCompanion(storedPath: Value(target.path)));
      if (!p.equals(source.absolute.path, target.absolute.path)) {
        await source.delete();
      }
      migrated++;
    }
    return migrated;
  }
}
