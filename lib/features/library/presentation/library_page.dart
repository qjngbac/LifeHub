import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/security/app_lock.dart';
import 'package:lifehub/features/library/data/saved_item_repository.dart';
import 'package:lifehub/features/library/presentation/collectibles_page.dart';
import 'package:lifehub/features/library/presentation/note_edit_page.dart';
import 'package:lifehub/shared/ui/app_lock_dialogs.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _query = TextEditingController();
  String _selectedFilter = 'ALL'; // 'ALL', 'PINNED', or tag name

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _formatRelativeTime(int timestamp) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24 && now.day == date.day) {
      return '今天 ${DateFormat('HH:mm').format(date)}';
    }
    if (diff.inDays == 1 || (diff.inHours < 48 && now.day - date.day == 1)) {
      return '昨天 ${DateFormat('HH:mm').format(date)}';
    }
    if (now.year == date.year) {
      return DateFormat('M月d日 HH:mm').format(date);
    }
    return DateFormat('yyyy年M月d日').format(date);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = SavedItemRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isTag = _selectedFilter != 'ALL' && _selectedFilter != 'PINNED';
    final isPinnedOnly = _selectedFilter == 'PINNED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('便签'),
        actions: [
          IconButton(
            tooltip: '收藏与链接',
            icon: const Icon(Icons.bookmark_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollectiblesPage()),
            ),
          ),
          IconButton(
            tooltip: '已归档便签',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _showArchivedNotes(repository),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NoteEditPage()),
          );
        },
        icon: const Icon(Icons.edit_note_rounded, size: 24),
        label: const Text('记便签'),
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: SearchBar(
              controller: _query,
              hintText: '搜索便签标题或内容...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _query.clear()),
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),

          // 2. Filter chips
          FutureBuilder<List<SavedItemEntry>>(
            future: repository.listNotes(),
            builder: (context, noteSnapshot) {
              final notes = noteSnapshot.data ?? [];
              final hasPinned = notes.any((n) => NoteMetadata.fromSourceUri(n.sourceUri).isPinned);

              return FutureBuilder<List<TagEntry>>(
                future: _loadAllTags(repository, notes),
                builder: (context, tagSnapshot) {
                  final tags = tagSnapshot.data ?? [];

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('全部 (${notes.length})'),
                          selected: _selectedFilter == 'ALL',
                          onSelected: (val) {
                            if (val) setState(() => _selectedFilter = 'ALL');
                          },
                        ),
                        if (hasPinned) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.push_pin, size: 14),
                            label: const Text('置顶'),
                            selected: _selectedFilter == 'PINNED',
                            onSelected: (val) {
                              if (val) setState(() => _selectedFilter = 'PINNED');
                            },
                          ),
                        ],
                        for (final tag in tags) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text('# ${tag.name}'),
                            selected: _selectedFilter == tag.name,
                            onSelected: (val) {
                              setState(() => _selectedFilter = val ? tag.name : 'ALL');
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // 3. Notes Content Grid / List
          Expanded(
            child: FutureBuilder<List<SavedItemEntry>>(
              future: repository.listNotes(
                query: _query.text,
                tag: isTag ? _selectedFilter : null,
                pinnedOnly: isPinnedOnly,
              ),
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
                          Icons.note_alt_outlined,
                          size: 64,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _query.text.isNotEmpty
                              ? '未找到与“${_query.text}”相关的便签'
                              : (_selectedFilter == 'PINNED'
                                  ? '暂无置顶便签'
                                  : '暂无便签，轻触右下角“记便签”开始'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final pinnedNotes = items
                    .where((n) => NoteMetadata.fromSourceUri(n.sourceUri).isPinned)
                    .toList();
                final normalNotes = items
                    .where((n) => !NoteMetadata.fromSourceUri(n.sourceUri).isPinned)
                    .toList();

                // 全部便签的标签一次性取回，卡片直接查表，避免逐条卡片的 N+1 查询
                return FutureBuilder<Map<String, List<TagEntry>>>(
                  future: repository.tagsForMany(items.map((e) => e.id)),
                  builder: (context, tagSnapshot) {
                    final tagsByNote =
                        tagSnapshot.data ?? const <String, List<TagEntry>>{};

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      children: [
                        // Section 1: Pinned Notes
                        if (_selectedFilter == 'ALL' &&
                            pinnedNotes.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Row(
                              children: [
                                Icon(Icons.push_pin,
                                    size: 16,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '置顶便签 (${pinnedNotes.length})',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final note in pinnedNotes)
                            _buildNoteCard(context, repository, note, isDark,
                                tagsByNote[note.id] ?? const <TagEntry>[]),
                          const SizedBox(height: 12),
                        ],

                        // Section 2: Other / Regular Notes
                        if (_selectedFilter == 'ALL' &&
                            pinnedNotes.isNotEmpty &&
                            normalNotes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Text(
                              '全部便签 (${normalNotes.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),

                        for (final note in (_selectedFilter == 'ALL' &&
                                pinnedNotes.isNotEmpty
                            ? normalNotes
                            : items))
                          _buildNoteCard(context, repository, note, isDark,
                              tagsByNote[note.id] ?? const <TagEntry>[]),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<TagEntry>> _loadAllTags(
    SavedItemRepository repository,
    List<SavedItemEntry> notes,
  ) async {
    // 一次批量查询取回全部便签的标签，避免逐条查询（N+1）。
    final tagsByNote = await repository.tagsForMany(notes.map((n) => n.id));
    final seenTagNames = <String>{};
    final result = <TagEntry>[];
    for (final note in notes) {
      for (final t in tagsByNote[note.id] ?? const <TagEntry>[]) {
        if (seenTagNames.add(t.name.toLowerCase())) {
          result.add(t);
        }
      }
    }
    return result;
  }

  Widget _buildNoteCard(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry note,
    bool isDark,
    List<TagEntry> tags,
  ) {
    final theme = Theme.of(context);
    final meta = NoteMetadata.fromSourceUri(note.sourceUri);
    final customColor = parseHexColor(meta.colorHex);

    Color cardBg;
    if (customColor != null) {
      cardBg = isDark ? Color.lerp(customColor, Colors.black, 0.72)! : customColor;
    } else {
      cardBg = isDark
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
          : Colors.white;
    }

    // 智能标题与正文摘要：若未写标题或标题是自动生成的，直接以首行为标题
    final rawContent = note.content?.trim() ?? '';
    final rawTitle = note.title.trim();

    String displayTitle = rawTitle;
    String displayBody = rawContent;

    if (rawContent.isNotEmpty) {
      final lines = rawContent.split('\n');
      final firstLine = lines.first.trim();
      final cleanFirstLine = firstLine
          .replaceFirst(RegExp(r'^(#+\s*|[-*•]\s*|\[[\sxX]\]\s*)'), '')
          .trim();

      // 只认"确实由正文自动生成"的标题：空标题、占位标题、与首行完全一致，
      // 或恰好是保存时"首行截断到 50 字 + …"的结果。
      // 绝不能用 startsWith 前缀判断——用户手写的标题若正好是首行前缀
      // （标题"购物清单"、首行"购物清单：西红柿"），会被正文首行顶掉。
      final autoTitle = cleanFirstLine.length > 50
          ? '${cleanFirstLine.substring(0, 50)}...'
          : cleanFirstLine;
      final isAutoTitle = rawTitle.isEmpty ||
          rawTitle == '无标题便签' ||
          rawTitle == cleanFirstLine ||
          rawTitle == firstLine ||
          (cleanFirstLine.length > 50 && rawTitle == autoTitle);

      if (isAutoTitle) {
        displayTitle = cleanFirstLine.isNotEmpty ? cleanFirstLine : '无标题便签';
        final remainingLines = lines.skip(1).join('\n').trim();
        displayBody = remainingLines;
      }
    } else if (displayTitle.isEmpty) {
      displayTitle = '无标题便签';
    }

    displayTitle = stripMarkdownDecorators(displayTitle);
    displayBody = stripMarkdownDecorators(displayBody);

    // 私密门禁：已设二级密码且未解锁 → 标题、摘要、标签一律遮罩，
    // 点击 / 长按都要先通过二级密码验证。
    final lock = ref.watch(appLockProvider);
    final locked = lock.configured && !lock.isUnlocked;
    final masked = locked && note.sensitive;
    if (masked) {
      displayTitle = '私密便签';
      displayBody = '';
    }

    final hasBody = displayBody.isNotEmpty;

    return Card(
      elevation: 0.5,
      color: cardBg,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: meta.isPinned
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: meta.isPinned ? 1.5 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (note.sensitive && locked) {
            final allowed =
                await ensureAppUnlocked(context, ref, title: '查看私密便签');
            if (!allowed || !context.mounted) return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NoteEditPage(initialNote: note),
            ),
          );
          // 退出便签详情页返回列表后，立即恢复私密锁定状态，防止列表明文泄露
          if (note.sensitive) {
            ref.read(appLockProvider.notifier).lock();
          }
          if (context.mounted) setState(() {});
        },
        onLongPress: () async {
          if (note.sensitive && locked) {
            final allowed =
                await ensureAppUnlocked(context, ref, title: '查看私密便签');
            if (!allowed || !context.mounted) return;
          }
          _showNoteOptions(context, repository, note, meta);
          if (note.sensitive) {
            ref.read(appLockProvider.notifier).lock();
          }
          if (context.mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题与置顶图标
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (meta.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Icon(
                        Icons.push_pin,
                        size: 15,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (note.sensitive)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Icon(
                        Icons.lock,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),

              // 正文内容摘要（仅在有剩余正文时展示，紧凑无多余空白）
              if (hasBody) ...[
                const SizedBox(height: 5),
                Text(
                  displayBody,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // 底部时间与标签
              Row(
                children: [
                  Text(
                    _formatRelativeTime(note.updatedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                  if (note.sensitive) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.lock, size: 12, color: theme.colorScheme.outline),
                  ],
                  const Spacer(),
                  for (final tag in (masked ? const <TagEntry>[] : tags).take(3)) ...[
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${tag.name}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNoteOptions(
    BuildContext context,
    SavedItemRepository repository,
    SavedItemEntry note,
    NoteMetadata meta,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  meta.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(meta.isPinned ? '取消置顶' : '置顶便签'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final refresh = ref.read(refreshProvider.notifier);
                  await repository.togglePin(note.id);
                  refresh.state++;
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制便签全文'),
                onTap: () {
                  Navigator.pop(ctx);
                  final full = [note.title, if (note.content != null) note.content!].join('\n\n');
                  Clipboard.setData(ClipboardData(text: full));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制便签全文到剪贴板')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('归档便签'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final refresh = ref.read(refreshProvider.notifier);
                  await repository.archive(note.id);
                  refresh.state++;
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已归档，可在右上角查看'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () async {
                          await repository.restore(note.id);
                          refresh.state++;
                        },
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除便签', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final refresh = ref.read(refreshProvider.notifier);
                  await repository.delete(note.id);
                  refresh.state++;
                  if (!context.mounted) return;
                  // 便签删除是可撤销的软删除，给用户一个后悔的机会
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已删除该便签'),
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () async {
                          await repository.restore(note.id);
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

  /// 归档后的便签原来只能去"我的 → 归档"里翻，而且类型显示成"资料"，
  /// 在便签页根本找不到。这里给便签页一个直达入口，支持查看与一键恢复。
  Future<void> _showArchivedNotes(SavedItemRepository repository) async {
    final archived = await repository.listNotes(archivedOnly: true);
    if (!mounted) return;
    // 归档里的私密便签同样要遮罩标题，否则换了入口就绕过保护了
    final lock = ref.read(appLockProvider);
    final locked = lock.configured && !lock.isUnlocked;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: archived.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('还没有归档的便签')),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Text(
                      '已归档便签 (${archived.length})',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  for (final note in archived)
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: Text(
                        (locked && note.sensitive) ? '私密便签' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatRelativeTime(note.updatedAt)),
                      trailing: TextButton(
                        onPressed: () async {
                          final refresh = ref.read(refreshProvider.notifier);
                          await repository.restore(note.id);
                          refresh.state++;
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已恢复到便签列表')),
                          );
                        },
                        child: const Text('恢复'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
