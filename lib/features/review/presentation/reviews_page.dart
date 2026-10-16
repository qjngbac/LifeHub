import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/review/data/review_repository.dart';

class ReviewsPage extends ConsumerStatefulWidget {
  const ReviewsPage({super.key});

  @override
  ConsumerState<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends ConsumerState<ReviewsPage> {
  String _periodType = 'WEEK';
  late DateTime _anchor = DateTime.now();
  final _wins = TextEditingController();
  final _blockers = TextEditingController();
  final _next = TextEditingController();
  int _revision = 0;
  String? _loadedReflectionPeriod;

  @override
  void dispose() {
    _wins.dispose();
    _blockers.dispose();
    _next.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _period {
    final day = DateTime(_anchor.year, _anchor.month, _anchor.day);
    if (_periodType == 'MONTH') {
      final start = DateTime(day.year, day.month);
      return (start, DateTime(day.year, day.month + 1));
    }
    final start = day.subtract(Duration(days: day.weekday - 1));
    return (start, start.add(const Duration(days: 7)));
  }

  void _move(int direction) {
    setState(() {
      _anchor = _periodType == 'MONTH'
          ? DateTime(_anchor.year, _anchor.month + direction)
          : _anchor.add(Duration(days: 7 * direction));
      _clearReflection();
    });
  }

  void _clearReflection() {
    _loadedReflectionPeriod = null;
    _wins.clear();
    _blockers.clear();
    _next.clear();
  }

  Future<ReviewSummary> _loadSummary(
      ReviewRepository repository, DateTime start, DateTime end) async {
    final type = _periodType;
    final key = '$type:${start.toIso8601String()}:${end.toIso8601String()}';
    final summary = await repository.summary(start, end);
    if (_loadedReflectionPeriod != key) {
      final saved = await repository.forPeriod(type, start, end);
      final current = _period;
      if (mounted && type == _periodType &&
          current.$1 == start && current.$2 == end) {
        _wins.text = saved?.wins ?? '';
        _blockers.text = saved?.blockers ?? '';
        _next.text = saved?.nextPriorities ?? '';
        _loadedReflectionPeriod = key;
      }
    }
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.read(databaseProvider);
    final repository = ReviewRepository(database);
    final (start, end) = _period;
    return Scaffold(
      appBar: AppBar(
        title: const Text('复盘'),
        actions: [
          IconButton(
            tooltip: '历史复盘',
            onPressed: () => _showHistory(context, repository),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: FutureBuilder<ReviewSummary>(
        key: ValueKey('$_revision:${start.toIso8601String()}'),
        future: _loadSummary(repository, start, end),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('复盘数据加载失败'));
          }
          if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'WEEK', label: Text('周复盘')),
                  ButtonSegment(value: 'MONTH', label: Text('月复盘')),
                ],
                selected: {_periodType},
                onSelectionChanged: (value) => setState(() {
                  _periodType = value.single;
                  _anchor = DateTime.now();
                  _clearReflection();
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一期',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel(start, end),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一期',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SummaryGrid(summary: summary),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_outlined, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            '写下这一期',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '记录本阶段心得与成长，沉淀在离线本地数据库。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _wins,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '做得好的事',
                          hintText: '完成了什么，有哪些收获？',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _blockers,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '阻碍与反思',
                          hintText: '哪些事阻碍了计划？',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _next,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '下一期优先项',
                          hintText: '最重要的三件事是什么？',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _save(repository, summary, start, end),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('保存复盘'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FutureBuilder<List<ReviewEntry>>(
                future: repository.list(),
                builder: (context, historySnapshot) {
                  final list = historySnapshot.data ?? const <ReviewEntry>[];
                  if (list.isEmpty) return const SizedBox.shrink();
                  final latest = list.take(2).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '最近复盘记录',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          TextButton(
                            onPressed: () => _showHistory(context, repository),
                            child: const Text('全部历史'),
                          ),
                        ],
                      ),
                      for (final item in latest)
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              item.periodType == 'MONTH'
                                  ? Icons.calendar_month_outlined
                                  : Icons.date_range_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                                item.periodType == 'MONTH' ? '月复盘' : '周复盘'),
                            subtitle: Text(
                              '${_dateKey(item.startDate)} — ${_dateKey(item.endDate)}',
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _showReviewDetail(context, item),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                '统计只描述本地记录到的事实，不代表效率评价、医学判断或因果结论。',
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  String _periodLabel(DateTime start, DateTime end) {
    if (_periodType == 'MONTH') return DateFormat('yyyy 年 M 月').format(start);
    return '${DateFormat('yyyy-MM-dd').format(start)} — '
        '${DateFormat('MM-dd').format(end.subtract(const Duration(days: 1)))}';
  }

  Future<void> _save(
    ReviewRepository repository,
    ReviewSummary summary,
    DateTime start,
    DateTime end,
  ) async {
    await repository.save(ReviewDraft(
      periodType: _periodType,
      start: start,
      end: end,
      summary: summary,
      wins: _wins.text,
      blockers: _blockers.text,
      nextPriorities: _next.text,
    ));
    if (!mounted) return;
    setState(() => _revision++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('复盘已保存，可在右上角历史中查看')),
    );
  }

  Future<void> _showHistory(
    BuildContext context,
    ReviewRepository repository,
  ) async {
    final reviews = await repository.list();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: reviews.isEmpty
              ? const Center(child: Text('还没有保存过复盘'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    final review = reviews[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(review.periodType == 'MONTH'
                            ? Icons.calendar_month_outlined
                            : Icons.date_range_outlined),
                        title:
                            Text(review.periodType == 'MONTH' ? '月复盘' : '周复盘'),
                        subtitle: Text(
                          '${_dateKey(review.startDate)} — ${_dateKey(review.endDate)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showReviewDetail(context, review),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _showReviewDetail(BuildContext context, ReviewEntry review) {
    final summary = jsonDecode(review.summaryJson) as Map<String, dynamic>;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(review.periodType == 'MONTH' ? '月复盘' : '周复盘'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('完成任务 ${summary['completedTasks'] ?? 0} · '
                  '习惯 ${summary['habitCheckIns'] ?? 0} · '
                  '专注 ${summary['focusMinutes'] ?? 0} 分钟'),
              _Reflection('做得好的事', review.wins),
              _Reflection('阻碍与反思', review.blockers),
              _Reflection('下一期优先项', review.nextPriorities),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _dateKey(int key) => DateFormat('yyyy-MM-dd').format(
        DateKeys.fromLocalDateKey(key),
      );
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});
  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.65,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          _Metric('完成任务', summary.completedTasks.toString(), Icons.task_alt,
              const Color(0xFF1E88E5)),
          _Metric('习惯打卡', summary.habitCheckIns.toString(), Icons.repeat,
              const Color(0xFF43A047)),
          _Metric('专注时间', '${summary.focusMinutes} 分钟', Icons.timer_outlined,
              const Color(0xFF7E57C2)),
          _Metric('进行中目标', summary.activeGoals.toString(), Icons.flag_outlined,
              const Color(0xFFFB8C00)),
          _Metric('心情记录', summary.moodDays.toString(),
              Icons.emoji_emotions_outlined, const Color(0xFFE91E63)),
          _Metric('每日事件', summary.lifeEvents.toString(),
              Icons.auto_stories_outlined, const Color(0xFF00897B)),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color.withValues(alpha: 0.95),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _Reflection extends StatelessWidget {
  const _Reflection(this.title, this.value);
  final String title;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(value?.trim().isNotEmpty == true ? value! : '未填写'),
          ],
        ),
      );
}
