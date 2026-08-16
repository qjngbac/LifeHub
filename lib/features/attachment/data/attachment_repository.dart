import 'dart:io';

import 'package:drift/drift.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AttachmentStorageSummary {
  const AttachmentStorageSummary(this.fileCount, this.totalBytes);
  final int fileCount;
  final int totalBytes;
}

class AttachmentRepository {
  AttachmentRepository(this._database, {Directory? storageRoot})
      : _storageRoot = storageRoot;

  final AppDatabase _database;
  final Directory? _storageRoot;

  Future<AttachmentEntry> importFile(
    String sourcePath, {
    String? displayName,
    String? mimeType,
    bool sensitive = false,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'File not found.');
    }
    final bytes = await source.readAsBytes();
    final digest = contentDigest(bytes);
    final duplicate = await (_database.select(_database.attachments)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.contentDigest.equals(digest) &
              row.byteSize.equals(bytes.length)))
        .getSingleOrNull();
    if (duplicate != null) return duplicate;

    final root = _storageRoot ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'lifehub_attachments'));
    await directory.create(recursive: true);
    final id = const Uuid().v4();
    final extension = p.extension(source.path).toLowerCase();
    final target = File(p.join(directory.path, '$id$extension'));
    await target.writeAsBytes(bytes, flush: true);
    await _database.into(_database.attachments).insert(
          AttachmentsCompanion.insert(
            id: Value(id),
            displayName: _safeName(displayName ?? p.basename(source.path)),
            storedPath: target.path,
            mimeType: Value(_optional(mimeType)),
            byteSize: bytes.length,
            contentDigest: digest,
            sensitive: Value(sensitive),
          ),
        );
    return get(id);
  }

  Future<AttachmentEntry> get(String id) async {
    final value = await (_database.select(_database.attachments)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (value == null) throw StateError('Attachment not found: $id');
    return value;
  }

  Future<void> link(
      String attachmentId, String entityType, String entityId) async {
    await get(attachmentId);
    final type = entityType.trim().toUpperCase();
    final target = entityId.trim();
    if (type.isEmpty || target.isEmpty) {
      throw ArgumentError('Invalid attachment link.');
    }
    final existing = await (_database.select(_database.attachmentLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.attachmentId.equals(attachmentId) &
              row.entityType.equals(type) &
              row.entityId.equals(target)))
        .getSingleOrNull();
    if (existing != null) return;
    await _database.into(_database.attachmentLinks).insert(
          AttachmentLinksCompanion.insert(
            attachmentId: attachmentId,
            entityType: type,
            entityId: target,
          ),
        );
  }

  Future<List<AttachmentEntry>> forEntity(
      String entityType, String entityId) async {
    final links = await (_database.select(_database.attachmentLinks)
          ..where((row) =>
              row.deletedAt.isNull() &
              row.entityType.equals(entityType.trim().toUpperCase()) &
              row.entityId.equals(entityId.trim())))
        .get();
    if (links.isEmpty) return const [];
    final ids = links.map((value) => value.attachmentId).toList();
    return (_database.select(_database.attachments)
          ..where((row) => row.deletedAt.isNull() & row.id.isIn(ids)))
        .get();
  }

  Future<void> unlink(
      String attachmentId, String entityType, String entityId) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (_database.update(_database.attachmentLinks)
          ..where((row) =>
              row.attachmentId.equals(attachmentId) &
              row.entityType.equals(entityType.trim().toUpperCase()) &
              row.entityId.equals(entityId.trim())))
        .write(AttachmentLinksCompanion(deletedAt: Value(now)));
  }

  Future<bool> unlinkAndDeleteOrphan(
    String attachmentId,
    String entityType,
    String entityId,
  ) async {
    await unlink(attachmentId, entityType, entityId);
    final remaining = await (_database.select(_database.attachmentLinks)
          ..where((row) =>
              row.deletedAt.isNull() & row.attachmentId.equals(attachmentId)))
        .getSingleOrNull();
    if (remaining != null) return false;
    final attachment = await get(attachmentId);
    final file = File(attachment.storedPath);
    if (await file.exists()) await file.delete();
    await (_database.delete(_database.attachments)
          ..where((row) => row.id.equals(attachmentId)))
        .go();
    return true;
  }

  Future<AttachmentStorageSummary> storageSummary() async {
    final values = await (_database.select(_database.attachments)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    return AttachmentStorageSummary(
      values.length,
      values.fold(0, (sum, value) => sum + value.byteSize),
    );
  }

  Future<int> deleteOrphans() async {
    final attachments = await (_database.select(_database.attachments)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    var deleted = 0;
    for (final attachment in attachments) {
      final link = await (_database.select(_database.attachmentLinks)
            ..where((row) =>
                row.deletedAt.isNull() &
                row.attachmentId.equals(attachment.id)))
          .getSingleOrNull();
      if (link != null) continue;
      final file = File(attachment.storedPath);
      if (await file.exists()) await file.delete();
      await (_database.delete(_database.attachments)
            ..where((row) => row.id.equals(attachment.id)))
          .go();
      deleted++;
    }
    return deleted;
  }

  static String contentDigest(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final value in bytes) {
      hash ^= value;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _safeName(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safe.isEmpty) return '附件';
    return safe.length > 500 ? safe.substring(0, 500) : safe;
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
