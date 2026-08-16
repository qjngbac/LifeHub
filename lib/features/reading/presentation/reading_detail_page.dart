import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/presentation/reading_form.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';

class ReadingDetailPage extends ConsumerStatefulWidget {
  const ReadingDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ReadingDetailPage> createState() => _ReadingDetailPageState();
}

class _ReadingDetailPageState extends ConsumerState<ReadingDetailPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = ReadingRepository(ref.read(databaseProvider));
    return FutureBuilder<ReadingItemEntry>(
      key: ValueKey(revision),
      future: repository.get(widget.itemId),
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(item.title),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) => _handleAction(repository, item, value),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '删除',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.author ?? '未填写作者'),
                      const SizedBox(height: 8),
                      Text(
                        item.totalProgress == null
                            ? '当前进度 ${item.currentProgress}'
                            : '当前进度 ${item.currentProgress}/${item.totalProgress}',
                      ),
                      if (item.rating != null) Text('评分 ${item.rating}/10'),
                      if (item.notes != null) ...[
                        const SizedBox(height: 12),
                        Text(item.notes!),
                      ],
                    ],
                  ),
                ),
              ),
              EntityRelationsPanel(
                entity: EntityReference(type: 'READING', id: item.id),
              ),
              AttachmentPanel(entityType: 'READING', entityId: item.id),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAction(
    ReadingRepository repository,
    ReadingItemEntry item,
    String action,
  ) async {
    if (action == 'edit') {
      final draft = await showReadingForm(context, current: item);
      if (draft == null) return;
      await repository.update(item.id, draft);
      if (mounted) setState(() => revision++);
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('删除这本读物？'),
            content: const Text('删除后将不再出现在阅读列表和搜索中。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await repository.delete(item.id);
    if (mounted) Navigator.pop(context);
  }
}
