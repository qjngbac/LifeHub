import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/data/attachment_repository.dart';
import 'package:lifehub/core/platform/attachment_open_service.dart';

class AttachmentPanel extends ConsumerWidget {
  const AttachmentPanel({
    required this.entityType,
    required this.entityId,
    this.sensitive = false,
    super.key,
  });
  final String entityType;
  final String entityId;
  final bool sensitive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = AttachmentRepository(ref.read(databaseProvider));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TextButton.icon(
              onPressed: () => _pick(context, ref, repository),
              icon: const Icon(Icons.attach_file),
              label: Text(
                '附件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ]),
          if (sensitive)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('敏感内容：仅保存在本机应用目录',
                  style: TextStyle(color: Colors.deepOrange)),
            ),
          FutureBuilder<List<AttachmentEntry>>(
            future: repository.forEntity(entityType, entityId),
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <AttachmentEntry>[];
              if (values.isEmpty) return const Text('暂无附件');
              return Column(children: [
                for (final value in values)
                  if (_isImage(value.storedPath))
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ImagePreview(
                            path: value.storedPath,
                            title: value.displayName,
                          ),
                        ),
                      ),
                      onLongPress: () =>
                          _remove(context, ref, repository, value),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(value.storedPath),
                            height: 150,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(
                                height: 80,
                                child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                      ),
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(value.displayName),
                      subtitle: Text(
                        '${(value.byteSize / 1024).toStringAsFixed(1)} KB · 点击打开',
                      ),
                      onTap: () => _open(context, value),
                      onLongPress: () =>
                          _remove(context, ref, repository, value),
                    ),
              ]);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    AttachmentRepository repository,
    AttachmentEntry value,
  ) async {
    final remove = await showModalBottomSheet<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: Text(value.displayName)),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除附件',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, true),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
            ]),
          ),
        ) ??
        false;
    if (!remove) return;
    await repository.unlinkAndDeleteOrphan(
      value.id,
      entityType,
      entityId,
    );
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _open(BuildContext context, AttachmentEntry value) async {
    final result = await AttachmentOpenService.open(value.storedPath);
    if (!context.mounted || result == AttachmentOpenResult.opened) return;
    final message = switch (result) {
      AttachmentOpenResult.missing => '附件文件已不存在',
      AttachmentOpenResult.noHandler => '手机上没有可打开此文件的应用',
      _ => '附件打开失败',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pick(BuildContext context, WidgetRef ref,
      AttachmentRepository repository) async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final attachment =
          await repository.importFile(path, sensitive: sensitive);
      await repository.link(attachment.id, entityType, entityId);
      ref.read(refreshProvider.notifier).state++;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('附件导入失败')));
      }
    }
  }
}

bool _isImage(String path) {
  final lower = path.toLowerCase();
  return const ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
      .any(lower.endsWith);
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path, required this.title});
  final String path;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(80),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text('图片无法显示', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      );
}
