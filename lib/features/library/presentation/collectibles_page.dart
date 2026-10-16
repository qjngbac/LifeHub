import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/presentation/note_edit_page.dart';
import 'package:lifehub/shared/ui/app_lock_dialogs.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

/// 收藏页：链接、文章、图片、文档等"非便签类资料"。
///
/// 这些条目原先在 App 内没有任何列表入口——全局快速新增的"收藏"、
/// 灵感库转存进来的链接都会变成孤儿数据，这里给它们一个家。
class CollectiblesPage extends ConsumerStatefulWidget {
  const CollectiblesPage({super.key});

  @override
  ConsumerState<CollectiblesPage> createState() => _CollectiblesPageState();
}

class _CollectiblesPageState extends ConsumerState<CollectiblesPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = SavedItemRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);

    final lock = ref.watch(appLockProvider);
    // 已设二级密码且当前未解锁 → 私密条目一律遮罩
    final locked = lock.configured && !lock.isUnlocked;

    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: FutureBuilder<List<SavedItemEntry>>(
        future: repository.listCollectibles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <SavedItemEntry>[];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有收藏内容\n在底部“快速新增 → 收藏”里可以存链接',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final item in items)
                _buildCard(context, repository, item, theme, locked),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
    ThemeData theme,
    bool locked,
  ) {
    final masked = locked && item.sensitive;
    final preview = masked ? '' : _preview(item);

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openItem(context, repository, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(item.itemType),
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            masked ? '私密收藏' : item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.sensitive) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('yyyy年M月d日 HH:mm')
                          .format(DateTime.fromMillisecondsSinceEpoch(item.updatedAt)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openItem(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
  ) async {
    if (item.sensitive) {
      final allowed = await ensureAppUnlocked(context, ref, title: '查看私密收藏');
      if (!allowed) return;
    }
    if (!context.mounted) return;
    _showActions(context, repository, item);
    if (item.sensitive) {
      ref.read(appLockProvider.notifier).lock();
    }
  }

  void _showActions(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制内容'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final full = [
                    item.title,
                    if (item.content != null) item.content!,
                  ].join('\n\n');
                  Clipboard.setData(ClipboardData(text: full));
                  _toast(context, '已复制');
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editItem(context, repository, item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  '删除收藏',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final refresh = ref.read(refreshProvider.notifier);
                  await repository.delete(item.id);
                  refresh.state++;
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已删除该收藏'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () async {
                          await repository.restore(item.id);
                          refresh.state++;
                        },
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editItem(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
  ) async {
    final titleController = TextEditingController(text: item.title);
    final contentController = TextEditingController(text: item.content ?? '');
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => KeyboardSafeFormDialog(
        title: const Text('编辑收藏'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: contentController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '链接或内容',
                hintText: '网址、摘录或备注',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // 必须在 dispose 之前取值，dispose 后再读 text 会抛异常
    final newTitle = titleController.text.trim();
    final newContent = contentController.text;
    titleController.dispose();
    contentController.dispose();
    if (saved != true) return;

    final refresh = ref.read(refreshProvider.notifier);
    await repository.updateCollectible(
      item.id,
      title: newTitle.isEmpty ? item.title : newTitle,
      content: newContent,
    );
    refresh.state++;
    if (!context.mounted) return;
    _toast(context, '已保存');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

IconData _iconFor(String itemType) => switch (itemType) {
      SavedItemType.link => Icons.link,
      SavedItemType.article => Icons.article_outlined,
      SavedItemType.image => Icons.image_outlined,
      SavedItemType.document => Icons.description_outlined,
      _ => Icons.bookmark_outline,
    };

String _preview(SavedItemEntry item) {
  final content = (item.content ?? '').trim();
  if (content.isEmpty) return '';
  return stripMarkdownDecorators(content)
      .replaceAll('\n', ' ')
      .trim();
}
