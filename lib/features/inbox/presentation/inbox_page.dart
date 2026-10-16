import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/presentation/bill_import_preview_page.dart';
import 'package:lifehub/features/inbox/data/inbox_repository.dart';
import 'package:lifehub/features/list/data/list_repository.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  String state = InboxState.newItem;
  final _quickController = TextEditingController();
  final _quickFocusNode = FocusNode();

  @override
  void dispose() {
    _quickController.dispose();
    _quickFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitQuick(InboxRepository repository) async {
    final text = _quickController.text.trim();
    if (text.isEmpty) return;
    _quickController.clear();
    HapticFeedback.lightImpact();
    await repository.capture(text);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = InboxRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感库'),
        actions: [
          IconButton(
            tooltip: '记录长灵感',
            icon: const Icon(Icons.edit_note_rounded, size: 26),
            onPressed: () => _capture(context, repository),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            8 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickController,
                  focusNode: _quickFocusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitQuick(repository),
                  decoration: InputDecoration(
                    hintText: '记录随时闪现的灵感火花（回车即存）…',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.outline,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                onPressed: () => _submitQuick(repository),
                tooltip: '存入灵感',
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: InboxState.newItem, label: Text('未处理')),
                ButtonSegment(value: InboxState.later, label: Text('稍后')),
                ButtonSegment(value: InboxState.processed, label: Text('已整理')),
                ButtonSegment(value: InboxState.archived, label: Text('已归档')),
              ],
              selected: {state},
              onSelectionChanged: (values) =>
                  setState(() => state = values.single),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InboxItemEntry>>(
              future: repository.list(state: state),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 56,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state == InboxState.newItem
                              ? '灵感库空空如也\n在下方直接输入，随时随手捕捉火花'
                              : '当前分类下暂无内容',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final canOrganize = state == InboxState.newItem ||
                        state == InboxState.later;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 头部元信息条
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(item.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '· ${_sourceLabel(item.sourceType)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                const Spacer(),
                                if (state == InboxState.processed)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _convertedLabel(item.convertedType),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 内容区域（轻触可复制）
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: item.content));
                                HapticFeedback.selectionClick();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已复制灵感内容到剪贴板'),
                                    duration: Duration(milliseconds: 1400),
                                  ),
                                );
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  item.content,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // 底部操作栏
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (canOrganize) ...[
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _organize(context, repository, item),
                                    icon: const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 16),
                                    label: const Text('整理为…'),
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  tooltip: '更多操作',
                                  icon: const Icon(Icons.more_vert_rounded,
                                      size: 20),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('修改内容'),
                                        ],
                                      ),
                                    ),
                                    if (state != InboxState.newItem)
                                      const PopupMenuItem(
                                        value: 'new',
                                        child: Row(
                                          children: [
                                            Icon(Icons.undo_rounded, size: 18),
                                            SizedBox(width: 8),
                                            Text('恢复到未处理'),
                                          ],
                                        ),
                                      ),
                                    if (state != InboxState.later &&
                                        state != InboxState.processed)
                                      const PopupMenuItem(
                                        value: 'later',
                                        child: Row(
                                          children: [
                                            Icon(Icons.alarm_rounded, size: 18),
                                            SizedBox(width: 8),
                                            Text('稍后处理'),
                                          ],
                                        ),
                                      ),
                                    if (state != InboxState.archived)
                                      const PopupMenuItem(
                                        value: 'archive',
                                        child: Row(
                                          children: [
                                            Icon(Icons.archive_outlined,
                                                size: 18),
                                            SizedBox(width: 8),
                                            Text('归档'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline,
                                              size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('删除',
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (action) async {
                                    if (action == 'delete') {
                                      await _confirmAndDelete(
                                          context, repository, item);
                                      return;
                                    }
                                    if (action == 'edit') {
                                      await _editContent(
                                        context,
                                        repository,
                                        item,
                                      );
                                      return;
                                    }
                                    await repository.setState(
                                      item.id,
                                      switch (action) {
                                        'new' => InboxState.newItem,
                                        'later' => InboxState.later,
                                        'archive' => InboxState.archived,
                                        _ => state,
                                      },
                                    );
                                    _refresh();
                                  },
                                ),
                              ],
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
        ],
      ),
    );
  }

  void _refresh() => ref.read(refreshProvider.notifier).state++;

  Future<void> _confirmAndDelete(
    BuildContext context,
    InboxRepository repository,
    InboxItemEntry item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除灵感'),
        content: Text(
          '确定删除这条灵感内容吗？\n\n"${item.content.length > 50 ? '${item.content.substring(0, 50)}...' : item.content}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.delete(item.id);
      _refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已删除该灵感'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                await repository.restore(item.id);
                _refresh();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _editContent(
    BuildContext context,
    InboxRepository repository,
    InboxItemEntry item,
  ) async {
    final controller = TextEditingController(text: item.content);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('修改灵感内容'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, '__DELETE__'),
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            label: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value == '__DELETE__') {
      if (context.mounted) {
        await _confirmAndDelete(context, repository, item);
      }
      return;
    }
    if (value.trim().isEmpty) return;
    await repository.updateContent(item.id, value);
    _refresh();
  }

  Future<void> _organize(
    BuildContext context,
    InboxRepository repository,
    InboxItemEntry item,
  ) async {
    final hasTimeKeyword = RegExp(
      r'今天|明天|后天|周[一二三四五六日天1-7]|点|时|分|月|日|号|\d{1,2}[:：]\d{2}',
    ).hasMatch(item.content);
    final isFilePath = item.content.toLowerCase().endsWith('.xlsx') ||
        item.content.toLowerCase().endsWith('.csv') ||
        item.content.toLowerCase().endsWith('.tsv') ||
        item.content.toLowerCase().endsWith('.zip');
    final hasBillKeyword = item.content.contains('微信支付账单') ||
        item.content.contains('支付宝交易') ||
        isFilePath ||
        (item.content.contains('交易单号') && item.content.contains('金额'));
    final action = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          const ListTile(
            title: Text('把这条灵感整理为…'),
            subtitle: Text('原文会保留在“已整理”中'),
          ),
          if (hasBillKeyword)
            ListTile(
              leading: Icon(Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.primary),
              title: const Text('财务流水（检测到账单数据，推荐）'),
              onTap: () => Navigator.pop(context, 'finance'),
            ),
          ListTile(
            leading: const Icon(Icons.task_alt_outlined),
            title: Text(hasTimeKeyword ? '任务（检测到时间，推荐）' : '任务'),
            onTap: () => Navigator.pop(context, 'task'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: const Text('清单项'),
            onTap: () => Navigator.pop(context, 'list'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(hasTimeKeyword ? '每日事件（检测到时间，推荐）' : '每日事件'),
            onTap: () => Navigator.pop(context, 'event'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('资料'),
            onTap: () => Navigator.pop(context, 'saved'),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('仅标记已整理'),
            onTap: () => Navigator.pop(context, 'retain'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'finance':
        List<ParsedBillItem> items = [];
        final maybeFile = File(item.content.trim());
        if (await maybeFile.exists()) {
          final fileName = maybeFile.uri.pathSegments.isNotEmpty
              ? maybeFile.uri.pathSegments.last
              : maybeFile.path;
          final bytes = await maybeFile.readAsBytes();
          items = BillCsvParser.parseBytes(bytes, fileName: fileName);
        } else {
          items = BillCsvParser.parse(item.content);
        }
        if (items.isNotEmpty) {
          await repository.retain(item.id);
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BillImportPreviewPage(rawItems: items),
            ),
          );
        } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未能在内容中解析到有效账单流水')),
          );
        }
      case 'task':
        await repository.convertToTask(item.id);
      case 'saved':
        await repository.convertToSavedItem(item.id);
      case 'retain':
        await repository.retain(item.id);
      case 'event':
        if (!context.mounted) return;
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (date == null) return;
        await repository.convertToDailyEvent(item.id, date);
      case 'list':
        if (!context.mounted) return;
        final listId = await _chooseList(context);
        if (listId == null) return;
        await repository.convertToListItem(item.id, listId);
    }
    if (!context.mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已整理，原文保留在已整理分类')),
    );
  }

  Future<String?> _chooseList(BuildContext context) async {
    final lists = await ListRepository(ref.read(databaseProvider)).lists();
    if (!context.mounted) return null;
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建一个清单')),
      );
      return null;
    }
    String selected = lists.first.id;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('选择清单'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: lists
                .map((list) => DropdownMenuItem(
                      value: list.id,
                      child: Text(list.title),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setLocal(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capture(
    BuildContext context,
    InboxRepository repository,
  ) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('记录灵感'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '记录脑海中的灵感火花，稍后再整理'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    await repository.capture(value);
    _refresh();
  }
}

String _sourceLabel(String value) => switch (value) {
      'ANDROID_SHARE' => '来自 Android 分享',
      'MANUAL' => '手工记录',
      _ => value,
    };

String _convertedLabel(String? value) => switch (value) {
      'TASK' => '已转为任务',
      'LIST_ITEM' => '已转为清单项',
      'LIFE_EVENT' => '已转为每日事件',
      'SAVED_ITEM' => '已存入资料库',
      'RETAINED' => '已保留',
      _ => '已处理',
    };

String _formatTime(int epochMillis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) {
    return '刚刚';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes}分钟前';
  } else if (diff.inHours < 24 && dt.day == now.day) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '今天 $hh:$mm';
  } else if (diff.inDays <= 1 && dt.day == now.subtract(const Duration(days: 1)).day) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '昨天 $hh:$mm';
  } else if (dt.year == now.year) {
    return '${dt.month}月${dt.day}日';
  } else {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
}
