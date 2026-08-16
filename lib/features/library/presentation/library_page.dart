import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = SavedItemRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('资料库')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, repository),
        icon: const Icon(Icons.add),
        label: const Text('添加便签'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _query,
            hintText: '搜索标题或内容',
            leading: const Icon(Icons.search),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SavedItemEntry>>(
            future: repository.search(_query.text),
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <SavedItemEntry>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (values.isEmpty) {
                return const Center(child: Text('暂无资料，可收藏笔记、链接和文档'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final item = values[index];
                  return Card(
                    child: ListTile(
                      leading:
                          CircleAvatar(child: Icon(_typeIcon(item.itemType))),
                      title: Text(item.title),
                      subtitle: Text(
                          [
                            if (item.content != null) item.content!,
                            '上次修改 ${_time(item.updatedAt)}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => _detail(context, repository, item),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _edit(context, repository, item);
                            return;
                          }
                          if (value == 'archive') {
                            await repository.archive(item.id);
                          }
                          if (value == 'delete') {
                            await repository.delete(item.id);
                          }
                          ref.read(refreshProvider.notifier).state++;
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('修改')),
                          PopupMenuItem(value: 'archive', child: Text('归档')),
                          PopupMenuItem(
                            value: 'delete',
                            child:
                                Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _create(
      BuildContext context, SavedItemRepository repository) async {
    final title = TextEditingController();
    final content = TextEditingController();
    final tags = TextEditingController();
    var sensitive = false;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(builder: (context, setLocal) {
        return KeyboardSafeFormDialog(
          title: const Text('添加便签'),
          body: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                  hintText: '不填写时使用“标题”',
                )),
            TextField(
              controller: content,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '便签内容'),
            ),
            TextField(
              controller: tags,
              decoration: const InputDecoration(
                labelText: '标签（可选）',
                hintText: '用逗号分隔，例如：旅行, 稍后阅读',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sensitive,
              title: const Text('敏感资料'),
              subtitle: const Text('不会出现在全局搜索中'),
              onChanged: (value) => setLocal(() => sensitive = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存')),
          ],
        );
      }),
    );
    final draft = created == true
        ? SavedItemDraft(
            title: title.text,
            itemType: SavedItemType.note,
            content: content.text,
            sensitive: sensitive,
          )
        : null;
    final tagNames = tags.text.split(RegExp(r'[,，]'));
    title.dispose();
    content.dispose();
    tags.dispose();
    if (draft == null) return;
    final item = await repository.create(draft);
    await repository.replaceTags(item.id, tagNames);
    ref.read(refreshProvider.notifier).state++;
  }

  Future<void> _edit(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
  ) async {
    final title = TextEditingController(text: item.title);
    final content = TextEditingController(text: item.content ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => KeyboardSafeFormDialog(
        title: const Text('修改便签'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: '标题（可选）'),
          ),
          TextField(
            controller: content,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(labelText: '便签内容'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final draft = accepted == true
        ? SavedItemDraft(
            title: title.text,
            content: content.text,
            sensitive: item.sensitive,
          )
        : null;
    title.dispose();
    content.dispose();
    if (draft == null) return;
    await repository.update(item.id, draft);
    ref.read(refreshProvider.notifier).state++;
  }

  void _detail(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry item,
  ) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(item.title)),
                  body: ListView(padding: const EdgeInsets.all(16), children: [
                    Text('上次修改 ${_time(item.updatedAt)}',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 12),
                    SelectableText(item.content ?? '暂无文本内容'),
                    const SizedBox(height: 12),
                    FutureBuilder<List<TagEntry>>(
                      future: repository.tagsFor(item.id),
                      builder: (context, snapshot) => Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final tag in snapshot.data ?? const <TagEntry>[])
                            Chip(label: Text(tag.name)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    EntityRelationsPanel(
                      entity: EntityReference(
                        type: 'SAVED_ITEM',
                        id: item.id,
                      ),
                    ),
                    AttachmentPanel(
                        entityType: 'SAVED_ITEM',
                        entityId: item.id,
                        sensitive: item.sensitive),
                  ]),
                )));
  }
}

IconData _typeIcon(String type) => switch (type) {
      SavedItemType.article => Icons.article_outlined,
      SavedItemType.link => Icons.link,
      SavedItemType.image => Icons.image_outlined,
      SavedItemType.document => Icons.description_outlined,
      _ => Icons.note_outlined,
    };

String _time(int milliseconds) {
  final value =
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true).toLocal();
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
