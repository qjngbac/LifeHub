import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/core/time/time_zone_resolver.dart';
import 'package:lifehub/features/matches/application/match_file_codecs.dart';
import 'package:lifehub/features/matches/application/match_import_service.dart';
import 'package:lifehub/features/matches/application/match_ocr_service.dart';
import 'package:lifehub/features/matches/data/match_repository.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/presentation/match_dialogs.dart';
import 'package:lifehub/features/matches/presentation/match_import_preview_page.dart';

class MatchSchedulePage extends ConsumerStatefulWidget {
  const MatchSchedulePage({
    super.key,
    this.rebuildNotifications,
  });

  final Future<void> Function(AppDatabase database)? rebuildNotifications;

  @override
  ConsumerState<MatchSchedulePage> createState() => _MatchSchedulePageState();
}

class _MatchSchedulePageState extends ConsumerState<MatchSchedulePage> {
  var tab = 0;
  var revision = 0;
  var query = '';
  var filters = const _MatchFilters();
  String? _lastUsedSport;

  @override
  Widget build(BuildContext context) {
    final repository = MatchRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('比赛日程'),
        actions: [
          IconButton(
            tooltip: '搜索比赛',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.search),
            onPressed: _search,
          ),
          IconButton(
            tooltip: '筛选比赛',
            visualDensity: VisualDensity.compact,
            color:
                filters.isActive ? Theme.of(context).colorScheme.primary : null,
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _filter,
          ),
          PopupMenuButton<String>(
            tooltip: '导出与更多',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert),
            onSelected: _export,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'export_ics',
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('导出赛程 (ICS 日历)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export_csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('导出赛程 (CSV 表格)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '添加比赛',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () => _add(repository),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('即将开始')),
              ButtonSegment(value: 1, label: Text('待补结果')),
              ButtonSegment(value: 2, label: Text('赛事档案')),
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.single),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<MatchRecordEntry>>(
              key: ValueKey('$revision:$tab:$query:$filters'),
              future: _load(repository),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('加载比赛失败：${snapshot.error}'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty && !filters.isActive
                          ? _emptyText(tab)
                          : '没有找到符合条件的比赛',
                    ),
                  );
                }
                if (tab == 2) {
                  return _ArchiveList(
                    rows: rows,
                    query: query.isEmpty ? null : query,
                    onTap: (row) => _openDetails(row),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _MatchCard(
                      row: row,
                      onTap: () => _openDetails(row),
                      onResult: tab == 1 ? () => _recordResult(row) : null,
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

  String _emptyText(int currentTab) =>
      currentTab == 1 ? '暂无待补结果的比赛' : '还没有比赛记录';

  Future<List<MatchRecordEntry>> _load(MatchRepository repository) {
    return switch (tab) {
      0 => repository.listUpcoming(
          now: DateTime.now(),
          query: query,
          sportType: filters.sportType,
          competition: filters.competition,
          from: filters.dateRange?.start,
          to: filters.dateRange?.end,
        ),
      1 => repository.listPendingResults(
          now: DateTime.now(),
          query: query,
          sportType: filters.sportType,
          competition: filters.competition,
          from: filters.dateRange?.start,
          to: filters.dateRange?.end,
        ),
      _ => repository.listArchive(
          query: query,
          year: filters.year,
          sportType: filters.sportType,
          competition: filters.competition,
          status: filters.status,
        ),
    };
  }

  Future<void> _filter() async {
    final result = await _showMatchFilters(
      context,
      current: filters,
      archive: tab == 2,
    );
    if (result != null && mounted) setState(() => filters = result);
  }

  Future<void> _search() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _SearchMatchDialog(initialQuery: query),
    );
    if (result != null && mounted) setState(() => query = result.trim());
  }

  Future<void> _add(MatchRepository repository) async {
    final choice = await showMatchImportChoice(context);
    if (!mounted || choice == null) return;
    if (choice == 'manual' || choice == 'finished') {
      final suggestions = await repository.getSuggestions();
      if (!mounted) return;
      final draft = await showMatchDraftDialog(
        context,
        finished: choice == 'finished',
        suggestions: suggestions,
        lastSport: _lastUsedSport,
      );
      if (draft == null) return;
      try {
        await repository.create(draft);
        _lastUsedSport = draft.sportType;
        await _rebuildNotifications();
        if (mounted) setState(() => revision++);
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
      return;
    }
    if (choice == 'text') {
      final parsed = await showTextImportDialog(context);
      if (parsed == null || !mounted || parsed.drafts.isEmpty) return;
      if (parsed.drafts.length == 1) {
        final suggestions = await repository.getSuggestions();
        if (!mounted) return;
        final draft = await showMatchDraftDialog(
          context,
          initial: parsed.drafts.first,
          suggestions: suggestions,
          lastSport: _lastUsedSport,
        );
        if (draft == null) return;
        try {
          await repository.create(draft);
          _lastUsedSport = draft.sportType;
          await _rebuildNotifications();
          if (mounted) setState(() => revision++);
        } on Object catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }
      } else {
        try {
          final preview =
              await MatchImportService().previewDraftsWithRepository(
            parsed.drafts,
            parsed.warnings,
            repository,
          );
          if (!mounted) return;
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => MatchImportPreviewPage(preview: preview),
            ),
          );
          if (saved == true && mounted) {
            await _rebuildNotifications();
            setState(() => revision++);
          }
        } on Object catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }
      }
      return;
    }
    if (choice == 'file') {
      await _importFile(repository);
    } else {
      await _importScreenshots(repository);
    }
  }

  Future<void> _importFile(MatchRepository repository) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'ics'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    try {
      final file = File(path);
      if (await file.length() > MatchFileCodecs.maxImportBytes) {
        throw const FormatException('比赛导入文件超过 5 MB 限制。');
      }
      final source = await file.readAsString();
      final preview = path.toLowerCase().endsWith('.ics')
          ? await MatchImportService()
              .previewIcsWithRepository(source, repository)
          : await MatchImportService()
              .previewCsvWithRepository(source, repository);
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => MatchImportPreviewPage(preview: preview)),
      );
      if (saved == true && mounted) {
        await _rebuildNotifications();
        setState(() => revision++);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _importScreenshots(MatchRepository repository) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    final paths =
        picked?.files.map((file) => file.path).whereType<String>().toList();
    if (paths == null || paths.isEmpty || !mounted) return;
    final ocr = MlKitMatchOcrService();
    try {
      final preview = await MatchImportService(ocrService: ocr).previewOcr(
        paths.map(File.new).toList(),
        referenceDate: DateTime.now(),
        repository: repository,
      );
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => MatchImportPreviewPage(preview: preview)),
      );
      if (saved == true && mounted) {
        await _rebuildNotifications();
        setState(() => revision++);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      await ocr.dispose();
    }
  }

  Future<void> _openDetails(MatchRecordEntry row) async {
    final repository = MatchRepository(ref.read(databaseProvider));
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title:
                  Text(row.status == MatchStatuses.postponed ? '确定新时间' : '编辑'),
              onTap: () => Navigator.pop(context, 'edit')),
          if (row.status == MatchStatuses.finished)
            ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('查看战报 / 复制'),
                onTap: () => Navigator.pop(context, 'report')),
          if (row.status == MatchStatuses.pendingResult)
            ListTile(
                leading: const Icon(Icons.scoreboard_outlined),
                title: const Text('补录结果'),
                onTap: () => Navigator.pop(context, 'result')),
          if (row.status == MatchStatuses.scheduled ||
              row.status == MatchStatuses.postponed)
            ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('取消比赛'),
                onTap: () => Navigator.pop(context, 'cancel')),
          if (row.status == MatchStatuses.scheduled)
            ListTile(
                leading: const Icon(Icons.update_outlined),
                title: const Text('延期比赛'),
                onTap: () => Navigator.pop(context, 'postpone')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'report') {
        await showMatchReportDialog(context, row);
        return;
      } else if (action == 'edit') {
        final suggestions = await repository.getSuggestions();
        if (!mounted) return;
        final draft = await showMatchDraftDialog(
          context,
          current: row,
          finished: row.status == MatchStatuses.finished,
          suggestions: suggestions,
        );
        if (draft != null) {
          await repository.update(
            row.id,
            row.status == MatchStatuses.postponed
                ? draft.copyWith(status: MatchStatuses.scheduled)
                : draft,
          );
        }
      } else if (action == 'result') {
        await _recordResult(row);
        return;
      } else if (action == 'postpone') {
        await repository.postpone(row.id);
      } else if (action == 'cancel') {
        await repository.setStatus(row.id, MatchStatuses.cancelled);
      } else if (action == 'delete') {
        await repository.delete(row.id);
      }
      await _rebuildNotifications();
      if (mounted) setState(() => revision++);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _export(String format) async {
    final repository = MatchRepository(ref.read(databaseProvider));
    final rows = await _load(repository);
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前视图没有可导出的比赛记录')),
        );
      }
      return;
    }
    try {
      if (format == 'export_ics') {
        final icsString = MatchFileCodecs.encodeIcs(rows);
        final bytes = Uint8List.fromList(utf8.encode(icsString));
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '导出比赛日程 (ICS)',
          fileName: 'matches.ics',
          type: FileType.custom,
          allowedExtensions: const ['ics'],
          bytes: bytes,
        );
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('赛程已导出为 ICS 日历文件')),
          );
        }
      } else if (format == 'export_csv') {
        final csvString = MatchFileCodecs.encodeCsv(rows);
        final bytes = Uint8List.fromList(utf8.encode(csvString));
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '导出比赛表格 (CSV)',
          fileName: 'matches.csv',
          type: FileType.custom,
          allowedExtensions: const ['csv'],
          bytes: bytes,
        );
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('赛程已导出为 CSV 表格文件')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    }
  }

  Future<void> _recordResult(MatchRecordEntry row) async {
    final draft =
        await showMatchDraftDialog(context, current: row, finished: true);
    if (draft == null || !mounted) return;
    final a = draft.scoreA;
    final b = draft.scoreB;
    if (a == null &&
        (draft.scoreDetail == null || draft.scoreDetail!.trim().isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写比分或结果说明')));
      return;
    }
    await MatchRepository(ref.read(databaseProvider)).recordResult(
      row.id,
      scoreA: a,
      scoreB: b,
      scoreDetail: draft.scoreDetail,
    );
    await _rebuildNotifications();
    if (mounted) setState(() => revision++);
  }

  Future<void> _rebuildNotifications() {
    final database = ref.read(databaseProvider);
    return widget.rebuildNotifications?.call(database) ??
        NotificationService.instance.rebuildFuture(database);
  }
}

class _MatchFilters {
  const _MatchFilters({
    this.sportType,
    this.competition,
    this.dateRange,
    this.year,
    this.status,
  });

  final String? sportType;
  final String? competition;
  final DateTimeRange? dateRange;
  final int? year;
  final String? status;

  bool get isActive =>
      sportType != null ||
      competition != null ||
      dateRange != null ||
      year != null ||
      status != null;

  @override
  String toString() =>
      '$sportType|$competition|${dateRange?.start}|${dateRange?.end}|$year|$status';
}

Future<_MatchFilters?> _showMatchFilters(
  BuildContext context, {
  required _MatchFilters current,
  required bool archive,
}) async {
  final sport = TextEditingController(text: current.sportType);
  final competition = TextEditingController(text: current.competition);
  final year = TextEditingController(text: current.year?.toString());
  var dateRange = current.dateRange;
  var status = current.status;
  String? error;
  final result = await showDialog<_MatchFilters>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('筛选比赛'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sport,
                decoration: const InputDecoration(
                  labelText: '运动类型',
                  hintText: '例如：足球',
                ),
              ),
              TextField(
                controller: competition,
                decoration: const InputDecoration(
                  labelText: '赛事',
                  hintText: '例如：英超',
                ),
              ),
              if (!archive)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('日期范围'),
                  subtitle: Text(dateRange == null
                      ? '全部日期'
                      : '${DateFormat('yyyy-MM-dd').format(dateRange!.start)} 至 '
                          '${DateFormat('yyyy-MM-dd').format(dateRange!.end)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDateRange: dateRange,
                    );
                    if (picked != null) setState(() => dateRange = picked);
                  },
                ),
              if (archive) ...[
                TextField(
                  controller: year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '年份',
                    hintText: '例如：2026',
                  ),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('全部')),
                    DropdownMenuItem(
                      value: MatchStatuses.finished,
                      child: Text('已结束'),
                    ),
                    DropdownMenuItem(
                      value: MatchStatuses.cancelled,
                      child: Text('已取消'),
                    ),
                  ],
                  onChanged: (value) => setState(() => status = value),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, const _MatchFilters()),
            child: const Text('重置'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final rawYear = year.text.trim();
              final parsedYear = rawYear.isEmpty ? null : int.tryParse(rawYear);
              if (rawYear.isNotEmpty &&
                  (parsedYear == null ||
                      parsedYear < 2000 ||
                      parsedYear > 2100)) {
                setState(() => error = '请输入 2000 至 2100 之间的年份。');
                return;
              }
              String? optional(String value) {
                final trimmed = value.trim();
                return trimmed.isEmpty ? null : trimmed;
              }

              Navigator.pop(
                dialogContext,
                _MatchFilters(
                  sportType: optional(sport.text),
                  competition: optional(competition.text),
                  dateRange: archive ? null : dateRange,
                  year: archive ? parsedYear : null,
                  status: archive ? status : null,
                ),
              );
            },
            child: const Text('应用'),
          ),
        ],
      ),
    ),
  );
  sport.dispose();
  competition.dispose();
  year.dispose();
  return result;
}

Widget _matchInfoText(IconData icon, String text, ThemeData theme) => Text.rich(
  TextSpan(
    children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(icon, size: 13, color: theme.colorScheme.outline),
      ),
      TextSpan(text: ' $text'),
    ],
  ),
  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
);

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.row, required this.onTap, this.onResult});

  final MatchRecordEntry row;
  final VoidCallback onTap;
  final VoidCallback? onResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = DateKeys.fromLocalDateKey(row.matchDate);
    final start = row.startAt == null
        ? null
        : TimeZoneResolver.atInstant(
            DateTime.fromMillisecondsSinceEpoch(row.startAt!, isUtc: true),
            row.timezoneId!,
          );

    final isFinished = row.status == MatchStatuses.finished;
    final isPendingResult = row.status == MatchStatuses.pendingResult;
    final isCancelled = row.status == MatchStatuses.cancelled;
    final isPostponed = row.status == MatchStatuses.postponed;
    final hasScore = row.scoreA != null && row.scoreB != null;

    final showYear = date.year != DateTime.now().year;
    final dateStr = showYear
        ? DateFormat('yyyy年M月d日').format(date)
        : DateFormat('M月d日').format(date);
    final timeStr = start == null
        ? ''
        : ' ${DateFormat('HH:mm').format(start)}';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final matchDay = DateTime(date.year, date.month, date.day);
    final isToday = matchDay == today;
    final isTomorrow = matchDay == tomorrow;

    String matchTimeText;
    String? relativeTag;
    Color? relativeTagColor;

    if (isFinished) {
      matchTimeText = '$dateStr$timeStr';
    } else if (row.status == MatchStatuses.scheduled) {
      if (start != null) {
        final diff = start.difference(now);
        if (diff.isNegative && diff > const Duration(hours: -3)) {
          relativeTag = '进行中';
          relativeTagColor = colorScheme.primary;
          matchTimeText = DateFormat('HH:mm').format(start);
        } else if (!diff.isNegative && diff.inMinutes < 60) {
          relativeTag = '${diff.inMinutes}分钟后';
          relativeTagColor = colorScheme.tertiary;
          matchTimeText = isToday
              ? '今天 ${DateFormat('HH:mm').format(start)}'
              : '$dateStr ${DateFormat('HH:mm').format(start)}';
        } else if (isToday) {
          relativeTag = diff.inHours > 0 ? '${diff.inHours}小时后' : null;
          relativeTagColor = colorScheme.secondary;
          matchTimeText = '今天 ${DateFormat('HH:mm').format(start)}';
        } else if (isTomorrow) {
          matchTimeText = '明天 ${DateFormat('HH:mm').format(start)}';
        } else {
          matchTimeText = '$dateStr$timeStr';
        }
      } else {
        matchTimeText = isToday ? '今天' : (isTomorrow ? '明天' : dateStr);
      }
    } else {
      matchTimeText = '$dateStr$timeStr';
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _sportIcon(row.sportType),
                  size: 22,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              Text(
                                row.competition,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (row.stageOrRound?.trim().isNotEmpty == true)
                                Text(
                                  row.stageOrRound!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isPostponed)
                          _statusTag(context, '已延期', colorScheme.error)
                        else if (isCancelled)
                          _statusTag(context, '已取消', colorScheme.outline)
                        else ...[
                          if (relativeTag != null) ...[
                            _statusTag(
                              context,
                              relativeTag,
                              relativeTagColor ?? colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            matchTimeText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            row.participantA,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 64),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasScore)
                                Text(
                                  '${row.scoreA} : ${row.scoreB}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isFinished
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                    letterSpacing: 2,
                                  ),
                                )
                              else if (isFinished || isPendingResult)
                                Text(
                                  '- : -',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.outline,
                                    letterSpacing: 2,
                                  ),
                                )
                              else
                                Text(
                                  'VS',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.outlineVariant,
                                    letterSpacing: 2,
                                  ),
                                ),
                              if (row.scoreDetail != null &&
                                  row.scoreDetail!.trim().isNotEmpty)
                                Text(
                                  row.scoreDetail!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.outline,
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row.participantB,
                            textAlign: TextAlign.left,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (row.venue != null ||
                        row.broadcast != null ||
                        onResult != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (row.venue?.trim().isNotEmpty == true)
                            _matchInfoText(
                              Icons.place_outlined,
                              row.venue!,
                              theme,
                            ),
                          if (row.broadcast?.trim().isNotEmpty == true)
                            _matchInfoText(
                              Icons.live_tv_outlined,
                              row.broadcast!,
                              theme,
                            ),
                          if (onResult != null)
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              onPressed: onResult,
                              child: const Text('补录'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusTag(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _sportIcon(String sport) => switch (sport) {
    '足球' => Icons.sports_soccer,
    '篮球' => Icons.sports_basketball,
    '网球' => Icons.sports_tennis,
    '电竞' => Icons.sports_esports_outlined,
    '羽毛球' => Icons.sports_tennis,
    '乒乓球' => Icons.sports_tennis,
    '排球' => Icons.sports_volleyball_outlined,
    '棒球' => Icons.sports_baseball_outlined,
    _ => Icons.emoji_events_outlined,
  };
}

class _ArchiveList extends StatelessWidget {
  const _ArchiveList({
    required this.rows,
    required this.onTap,
    this.query,
  });

  final List<MatchRecordEntry> rows;
  final ValueChanged<MatchRecordEntry> onTap;
  final String? query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final finishedCount =
        rows.where((r) => r.status == MatchStatuses.finished).length;
    final cancelledCount =
        rows.where((r) => r.status == MatchStatuses.cancelled).length;

    Widget? statsBanner;
    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      int matches = 0;
      int wins = 0;
      int draws = 0;
      int losses = 0;
      int goalsFor = 0;
      int goalsAgainst = 0;
      for (final row in rows) {
        final isA = row.participantA.toLowerCase().contains(q);
        final isB = row.participantB.toLowerCase().contains(q);
        if (!isA && !isB) continue;
        if (row.scoreA != null && row.scoreB != null) {
          matches++;
          final sa = row.scoreA!;
          final sb = row.scoreB!;
          if (isA) {
            goalsFor += sa;
            goalsAgainst += sb;
            if (sa > sb) {
              wins++;
            } else if (sa == sb) {
              draws++;
            } else {
              losses++;
            }
          } else {
            goalsFor += sb;
            goalsAgainst += sa;
            if (sb > sa) {
              wins++;
            } else if (sb == sa) {
              draws++;
            } else {
              losses++;
            }
          }
        }
      }
      if (matches > 0) {
        final winRate = (wins / matches * 100).toStringAsFixed(1);
        final diff = goalsFor - goalsAgainst;
        final diffStr = diff > 0 ? '+$diff' : '$diff';
        statsBanner = Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.query_stats,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '“${query!.trim()}” 战绩看板',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '胜率 $winRate%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '总场次：$matches 场',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '战绩：$wins 胜 $draws 平 $losses 负',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '得失球：$goalsFor / $goalsAgainst ($diffStr)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    } else {
      statsBanner = Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          '档案统计：共收录 ${rows.length} 场 · 已完赛 $finishedCount 场 · 已取消 $cancelledCount 场',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
      );
    }

    final grouped = <int, Map<String, Map<String, List<MatchRecordEntry>>>>{};
    for (final row in rows) {
      final year = DateKeys.fromLocalDateKey(row.matchDate).year;
      final sports = grouped.putIfAbsent(year, () => {});
      final competitions = sports.putIfAbsent(row.sportType, () => {});
      competitions.putIfAbsent(row.competition, () => []).add(row);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        ?statsBanner,
        for (final entry in grouped.entries)
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            initiallyExpanded: true,
            title: Text(
              '${entry.key} 年 · '
              '${entry.value.values.expand((competitions) => competitions.values).fold<int>(0, (sum, rows) => sum + rows.length)} 场',
            ),
            children: [
              for (final sport in entry.value.entries)
                ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(sport.key),
                  subtitle: Text(
                    '${sport.value.values.fold<int>(0, (sum, rows) => sum + rows.length)} 场',
                  ),
                  children: [
                    for (final competition in sport.value.entries)
                      ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(competition.key),
                        subtitle: Text('${competition.value.length} 场'),
                        children: [
                          for (final row in competition.value)
                            _MatchCard(row: row, onTap: () => onTap(row)),
                        ],
                      ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

class _SearchMatchDialog extends StatefulWidget {
  final String initialQuery;
  const _SearchMatchDialog({required this.initialQuery});

  @override
  State<_SearchMatchDialog> createState() => _SearchMatchDialogState();
}

class _SearchMatchDialogState extends State<_SearchMatchDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索比赛'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '赛事、球队或选手'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('搜索'),
        ),
      ],
    );
  }
}
