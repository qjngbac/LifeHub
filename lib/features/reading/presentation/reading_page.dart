import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/reading/data/reading_repository.dart';
import 'package:lifehub/features/reading/domain/reading_models.dart';
import 'package:lifehub/features/reading/presentation/reading_detail_page.dart';
import 'package:lifehub/features/reading/presentation/reading_form.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({super.key});

  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage> {
  var query = '';
  ReadingType? selectedType;
  var statusFilter = 'ALL';
  var revision = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = ReadingRepository(ref.read(databaseProvider));

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读进度'),
        actions: [
          if (selectedType != null || statusFilter != 'ALL')
            TextButton(
              onPressed: () {
                setState(() {
                  selectedType = null;
                  statusFilter = 'ALL';
                });
              },
              child: const Text('重置筛选'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('添加读物'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              hintText: '搜索书名、作者或备注',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: query.trim().isNotEmpty
                ? _buildSearchResults(repository)
                : _buildHomeContent(repository),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ReadingRepository repository) {
    return FutureBuilder<List<ReadingItemEntry>>(
      key: ValueKey('$revision-$query'),
      future: repository.search(query),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '未找到与 "$query" 相关的读物',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: rows.length,
          itemBuilder: (context, index) =>
              _buildBookItemCard(repository, rows[index]),
        );
      },
    );
  }

  Widget _buildHomeContent(ReadingRepository repository) {
    return FutureBuilder<List<ReadingItemEntry>>(
      key: ValueKey(revision),
      future: repository.list(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allRows = snapshot.data!;
        if (allRows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有阅读记录',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '记录正在阅读的小说、图书或论文，\n随手打卡不再遗忘进度。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _add(repository),
                    icon: const Icon(Icons.add),
                    label: const Text('添加第一本读物'),
                  ),
                ],
              ),
            ),
          );
        }

        final scopeRows = selectedType == null
            ? allRows
            : allRows
                .where((r) => _parseType(r.readingType) == selectedType)
                .toList();

        var filteredRows = [...scopeRows];
        if (statusFilter != 'ALL') {
          filteredRows =
              filteredRows.where((r) => r.status == statusFilter).toList();
        }
        filteredRows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            // 1. 读物分类网格（两行6个分类：全部 + 5个类型）
            _SectionTitle(
              '读物分类',
              action: selectedType != null
                  ? TextButton(
                      onPressed: () => setState(() => selectedType = null),
                      child: const Text('显示全部'),
                    )
                  : null,
            ),
            GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.05,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildCategoryCard(null, allRows.length, selectedType == null),
                ...ReadingType.values.map((t) {
                  final count = allRows
                      .where((r) => _parseType(r.readingType) == t)
                      .length;
                  return _buildCategoryCard(t, count, selectedType == t);
                }),
              ],
            ),
            const SizedBox(height: 12),

            // 2. 按状态查看胶囊栏（与当前选中读物分类联动统计）
            const _SectionTitle('按状态查看'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip('ALL', '全部', scopeRows.length, Colors.blue),
                _buildStatusChip(
                  'READING',
                  '在读',
                  scopeRows.where((r) => r.status == 'READING').length,
                  Colors.blueAccent,
                ),
                _buildStatusChip(
                  'PLANNED',
                  '想读',
                  scopeRows.where((r) => r.status == 'PLANNED').length,
                  Colors.orange,
                ),
                _buildStatusChip(
                  'COMPLETED',
                  '已读完',
                  scopeRows.where((r) => r.status == 'COMPLETED').length,
                  Colors.green,
                ),
                _buildStatusChip(
                  'PAUSED',
                  '搁置',
                  scopeRows.where((r) => r.status == 'PAUSED').length,
                  Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3. 读物列表
            _SectionTitle(
              selectedType != null
                  ? '${readingTypeLabel(selectedType!)} · ${_statusName(statusFilter)} (${filteredRows.length})'
                  : '${_statusName(statusFilter)}读物 (${filteredRows.length})',
            ),
            if (filteredRows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    '当前分类与状态下暂无读物',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              for (final row in filteredRows)
                _buildBookItemCard(repository, row),
          ],
        );
      },
    );
  }

  Widget _buildCategoryCard(ReadingType? t, int count, bool isSelected) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = t == null ? colorScheme.primary : _categoryColor(t);
    final icon = t == null ? Icons.auto_stories_rounded : readingTypeIcon(t);
    final label = t == null ? '全部' : readingTypeLabel(t);

    return Material(
      color: isSelected
          ? color.withValues(alpha: 0.15)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? color
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: isSelected ? 1.5 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            selectedType = t;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$count 本',
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? color : colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    String statusKey,
    String label,
    int count,
    Color dotColor,
  ) {
    final isSelected = statusFilter == statusKey;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ActionChip(
      avatar: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
        ),
      ),
      label: Text('$label $count'),
      backgroundColor: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.outlineVariant.withValues(alpha: 0.4),
        width: isSelected ? 1.2 : 0.8,
      ),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color:
            isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
      ),
      onPressed: () {
        setState(() => statusFilter = statusKey);
      },
    );
  }


  Widget _buildBookItemCard(
    ReadingRepository repository,
    ReadingItemEntry row,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasTotal = row.totalProgress != null && row.totalProgress! > 0;
    final fraction = hasTotal
        ? (row.currentProgress / row.totalProgress!).clamp(0.0, 1.0)
        : null;
    final percent =
        fraction != null ? (fraction * 100).toStringAsFixed(0) : null;
    final unit = _unit(row.progressUnit);
    final isFinished = row.status == 'COMPLETED' ||
        (hasTotal && row.currentProgress >= row.totalProgress!);
    final typeEnum = _parseType(row.readingType);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReadingDetailPage(itemId: row.id),
            ),
          );
          if (mounted) setState(() => revision++);
        },
        onLongPress: () => _confirmDelete(repository, row),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBookCover(typeEnum, size: const Size(42, 56)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (row.author?.isNotEmpty == true)
                              Text(
                                row.author!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${readingTypeLabel(typeEnum)} · $unit',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.outline,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isFinished)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Colors.green,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '已读完',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '修改进度',
                          icon: const Icon(Icons.edit_note_rounded, size: 22),
                          onPressed: () => _editProgress(repository, row),
                        ),
                        IconButton.filledTonal(
                          tooltip: '进度+1',
                          icon: const Icon(Icons.add_rounded, size: 20),
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            try {
                              await repository.updateProgress(
                                row.id,
                                row.currentProgress + 1,
                              );
                              if (mounted) setState(() => revision++);
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '更新失败：${e is RangeError ? "已达全书总数" : e.toString()}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (fraction != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor:
                        colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                const SizedBox(height: 5),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _editProgress(repository, row),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      child: Text(
                        hasTotal
                            ? '进度：${row.currentProgress} / ${row.totalProgress} $unit'
                            : '已读：${row.currentProgress} $unit',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (percent != null)
                    Text(
                      '$percent%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookCover(ReadingType typeEnum, {required Size size}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.25),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              readingTypeIcon(typeEnum),
              color: colorScheme.primary,
              size: size.width * 0.45,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProgress(
    ReadingRepository repository,
    ReadingItemEntry row,
  ) async {
    final ctrl = TextEditingController(text: '${row.currentProgress}');
    final unit = _unit(row.progressUnit);
    String? errorText;

    final next = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('更新《${row.title}》进度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.totalProgress != null && row.totalProgress! > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '全书共 ${row.totalProgress} $unit',
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
                  labelText: '当前已读进度',
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
              if (row.totalProgress != null && row.totalProgress! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('设为已读完 (${row.totalProgress} $unit)'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      ctrl.text = '${row.totalProgress}';
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
                if (row.totalProgress != null &&
                    row.totalProgress! > 0 &&
                    val > row.totalProgress!) {
                  setDlgState(() => errorText =
                      '输入进度 ($val) 不能超过全书总数 (${row.totalProgress} $unit)');
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
      try {
        await repository.updateProgress(row.id, next);
        if (mounted) {
          setState(() => revision++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已更新《${row.title}》进度至 $next $unit'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '更新进度失败：${e is RangeError ? "进度不能超过全书总数" : e.toString()}',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmDelete(
    ReadingRepository repository,
    ReadingItemEntry row,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除读物'),
        content: Text(
          '确定删除《${row.title}》吗？删除后将不再出现在阅读列表和搜索中。',
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
    if (confirmed == true && mounted) {
      await repository.delete(row.id);
      if (mounted) {
        setState(() => revision++);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除《${row.title}》')),
        );
      }
    }
  }

  Future<void> _add(ReadingRepository repository) async {
    final draft = await showReadingForm(context);
    if (draft == null) return;
    await repository.create(draft);
    if (mounted) setState(() => revision++);
  }

  ReadingType _parseType(String typeStr) {
    return ReadingType.values.firstWhere(
      (e) => e.name.toUpperCase() == typeStr.toUpperCase(),
      orElse: () => ReadingType.novel,
    );
  }

  Color _categoryColor(ReadingType t) => switch (t) {
        ReadingType.book => Colors.indigo,
        ReadingType.novel => Colors.deepPurple,
        ReadingType.comic => Colors.deepOrange,
        ReadingType.paper => Colors.teal,
        ReadingType.other => Colors.blueGrey,
      };

  String _statusName(String status) => switch (status) {
        'ALL' => '全部',
        'READING' => '在读',
        'PLANNED' => '想读',
        'COMPLETED' => '已读完',
        'PAUSED' => '搁置',
        'DROPPED' => '弃读',
        _ => status,
      };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
          ),
          ?action,
        ],
      ),
    );
  }
}

String _unit(String value) => switch (value) {
      'PAGE' => '页',
      'CHAPTER' => '章',
      'PERCENT' => '%',
      _ => value,
    };
