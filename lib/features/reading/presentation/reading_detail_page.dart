import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<ReadingItemEntry>(
      key: ValueKey(revision),
      future: repository.get(widget.itemId),
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                (item == null || item.deletedAt != null))) {
          return Scaffold(
            appBar: AppBar(title: const Text('读物详情')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snapshot.hasError ? '加载失败，记录可能不存在或已删除' : '记录不存在或已删除'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => revision++),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('读物详情')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final hasTotal = item.totalProgress != null && item.totalProgress! > 0;
        final fraction = hasTotal
            ? (item.currentProgress / item.totalProgress!).clamp(0.0, 1.0)
            : null;
        final percent = fraction != null
            ? (fraction * 100).toStringAsFixed(0)
            : null;
        final unit = readingUnitLabel(item.progressUnit);
        final typeEnum = _parseType(item.readingType);
        final isFinished = item.status == 'COMPLETED' ||
            (hasTotal && item.currentProgress >= item.totalProgress!);

        return Scaffold(
          appBar: AppBar(
            title: const Text('读物详情'),
            actions: [
              IconButton(
                tooltip: '编辑读物',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _handleAction(repository, item, 'edit'),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleAction(repository, item, value),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          '删除读物',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // 头部大书影卡片
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 书卷封面拟态
                      Container(
                        width: 58,
                        height: 78,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.25),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(10),
                                    bottomLeft: Radius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Icon(
                                readingTypeIcon(typeEnum),
                                color: colorScheme.primary,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 书籍详情文字
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.author?.isNotEmpty == true
                                  ? item.author!
                                  : '未填写作者',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${readingTypeLabel(typeEnum)} · $unit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.outline,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isFinished
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : colorScheme.primaryContainer
                                            .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    readingStatusLabel(item.status),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isFinished
                                          ? Colors.green
                                          : colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (item.rating != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 13, color: Colors.amber),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${item.rating} 分',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 进度仪表板与快捷微调操作台
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.trending_up_rounded,
                                  size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '阅读进度追踪',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (percent != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$percent%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 进度数值指示
                      Text(
                        hasTotal
                            ? '${item.currentProgress} / ${item.totalProgress} $unit'
                            : '已读 ${item.currentProgress} $unit',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 胶囊进度条
                      if (fraction != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 8,
                            backgroundColor: colorScheme.outlineVariant
                                .withValues(alpha: 0.25),
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // 步进微调按钮群
                      Text(
                        '快速打卡微调',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (item.currentProgress > 0)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.remove, size: 16),
                              label: const Text('-1'),
                              onPressed: () => _updateRelative(
                                  repository, item, -1),
                            ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+1'),
                            onPressed: () => _updateRelative(
                                repository, item, 1),
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+5'),
                            onPressed: () => _updateRelative(
                                repository, item, 5),
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.edit_note_rounded, size: 16),
                            label: const Text('指定进度'),
                            onPressed: () => _editProgressDialog(
                                repository, item),
                          ),
                          if (!isFinished && hasTotal)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              icon: const Icon(Icons.done_all_rounded, size: 16),
                              label: const Text('读完此书'),
                              onPressed: () => _markCompleted(
                                  repository, item),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 笔记与读后感
              if (item.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.format_quote_rounded,
                                size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '读书笔记与随感',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            item.notes!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              EntityRelationsPanel(
                entity: EntityReference(type: 'READING', id: item.id),
              ),
              const SizedBox(height: 8),
              AttachmentPanel(entityType: 'READING', entityId: item.id),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRelative(
    ReadingRepository repository,
    ReadingItemEntry item,
    int delta,
  ) async {
    final next = (item.currentProgress + delta).clamp(
      0,
      item.totalProgress ?? 9999999,
    );
    HapticFeedback.lightImpact();
    await repository.updateProgress(item.id, next);
    if (mounted) setState(() => revision++);
  }

  Future<void> _markCompleted(
    ReadingRepository repository,
    ReadingItemEntry item,
  ) async {
    if (item.totalProgress == null || item.totalProgress! <= 0) return;
    HapticFeedback.mediumImpact();
    await repository.updateProgress(item.id, item.totalProgress!);
    if (mounted) setState(() => revision++);
  }

  Future<void> _editProgressDialog(
    ReadingRepository repository,
    ReadingItemEntry item,
  ) async {
    final ctrl = TextEditingController(text: '${item.currentProgress}');
    final unit = readingUnitLabel(item.progressUnit);
    String? errorText;
    final next = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('修改《${item.title}》进度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.totalProgress != null && item.totalProgress! > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '全书共 ${item.totalProgress} $unit',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '当前进度 ($unit)',
                  border: const OutlineInputBorder(),
                  suffixText: unit,
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDlgState(() => errorText = null);
                  }
                },
              ),
              if (item.totalProgress != null && item.totalProgress! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('设为已读完 (${item.totalProgress} $unit)'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      ctrl.text = '${item.totalProgress}';
                      setDlgState(() => errorText = null);
                    },
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final val = int.tryParse(ctrl.text.trim());
                if (val == null || val < 0) {
                  setDlgState(() => errorText = '请输入大于或等于 0 的有效数字');
                  return;
                }
                if (item.totalProgress != null &&
                    item.totalProgress! > 0 &&
                    val > item.totalProgress!) {
                  setDlgState(() => errorText =
                      '输入进度 ($val) 不能超过全书总数 (${item.totalProgress} $unit)');
                  return;
                }
                Navigator.pop(ctx, val);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (next != null && mounted) {
      HapticFeedback.lightImpact();
      try {
        await repository.updateProgress(item.id, next);
        if (mounted) {
          setState(() => revision++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已更新《${item.title}》进度至 $next $unit'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('更新进度失败：${e is RangeError ? "进度不能超过全书总数" : e.toString()}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
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
            content: Text(
              '确定删除《${item.title}》吗？删除后将不再出现在阅读列表和搜索中。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  ReadingType _parseType(String typeStr) {
    return ReadingType.values.firstWhere(
      (e) => e.name.toUpperCase() == typeStr.toUpperCase(),
      orElse: () => ReadingType.novel,
    );
  }
}
