import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

class FinanceAnalyticsPage extends ConsumerStatefulWidget {
  const FinanceAnalyticsPage({super.key});

  @override
  ConsumerState<FinanceAnalyticsPage> createState() =>
      _FinanceAnalyticsPageState();
}

class _FinanceAnalyticsPageState extends ConsumerState<FinanceAnalyticsPage> {
  DateTime _selectedMonth = DateTime.now();

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final database = ref.watch(databaseProvider);
    final financeRepo = FinanceRepository(database);
    final accountRepo = AccountRepository(database);

    final monthTitle = DateFormat('yyyy年M月').format(_selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('财务洞察与深度分析'),
      ),
      body: FutureBuilder<List<Object>>(
        key: ValueKey('analytics_${_selectedMonth.year}_${_selectedMonth.month}'),
        future: Future.wait<Object>([
          financeRepo.richMonthlySummary(_selectedMonth.year, _selectedMonth.month),
          accountRepo.listAccounts(),
          financeRepo.list(
            start: DateTime(_selectedMonth.year, _selectedMonth.month),
            end: DateTime(_selectedMonth.year, _selectedMonth.month + 1),
          ),
          financeRepo.richMonthlySummary(
            _selectedMonth.month == 1 ? _selectedMonth.year - 1 : _selectedMonth.year,
            _selectedMonth.month == 1 ? 12 : _selectedMonth.month - 1,
          ),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = snapshot.data![0] as RichFinanceSummary;
          final accounts = snapshot.data![1] as List<FinanceAccountEntry>;
          final entries = snapshot.data![2] as List<FinanceEntry>;
          final prevSummary = snapshot.data![3] as RichFinanceSummary;
          final accountMap = {for (final a in accounts) a.id: a};

          final netBalance = summary.incomeMinor - summary.expenseMinor;
          final savingsRate = summary.incomeMinor > 0
              ? (netBalance / summary.incomeMinor * 100).clamp(-100.0, 100.0)
              : 0.0;

          final prevMonthDate = DateTime(
            _selectedMonth.month == 1 ? _selectedMonth.year - 1 : _selectedMonth.year,
            _selectedMonth.month == 1 ? 12 : _selectedMonth.month - 1,
            1,
          );

          // Compute account spending distribution
          final spendingByAccount = <String, int>{};
          for (final e in entries) {
            if (e.direction == FinanceDirection.expense && !e.isReimbursable) {
              final accName = e.accountId != null
                  ? accountMap[e.accountId]?.name ?? '未分配渠道'
                  : '未分配渠道';
              spendingByAccount[accName] =
                  (spendingByAccount[accName] ?? 0) + e.amountMinor;
            }
          }

          // Compute out-of-town / special tag totals
          int outOfTownExpenseMinor = 0;
          final specialTagTotals = <String, int>{};
          for (final e in entries) {
            if (e.direction == FinanceDirection.expense && e.tagsJson != null) {
              final tags = summary.tagBreakdown.keys;
              for (final t in tags) {
                if (e.tagsJson!.contains(t)) {
                  specialTagTotals[t] =
                      (specialTagTotals[t] ?? 0) + e.amountMinor;
                  if (t == '异地消费' || t == '差旅出差' || t == '老家探亲' || t == '旅游度假') {
                    outOfTownExpenseMinor += e.amountMinor;
                  }
                }
              }
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // Month Selector Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _previousMonth,
                  ),
                  Text(
                    monthTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _nextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Macro Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatColumn(
                            title: '当月总收入',
                            value:
                                '¥${(summary.incomeMinor / 100).toStringAsFixed(2)}',
                            color: Colors.green,
                            theme: theme,
                          ),
                          Container(
                              height: 36,
                              width: 1,
                              color: colorScheme.outlineVariant),
                          _buildStatColumn(
                            title: '当月总支出',
                            value:
                                '¥${(summary.expenseMinor / 100).toStringAsFixed(2)}',
                            color: colorScheme.error,
                            theme: theme,
                          ),
                          Container(
                              height: 36,
                              width: 1,
                              color: colorScheme.outlineVariant),
                          _buildStatColumn(
                            title: '结余率',
                            value: '${savingsRate.toStringAsFixed(1)}%',
                            color: netBalance >= 0
                                ? colorScheme.primary
                                : colorScheme.error,
                            theme: theme,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Month-over-Month Comparison Card
              _buildMonthOverMonthCard(
                current: summary,
                previous: prevSummary,
                previousMonthDate: prevMonthDate,
                theme: theme,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 14),

              // Daily Spending Trend Card
              _buildDailyTrendCard(
                entries: entries,
                selectedMonth: _selectedMonth,
                totalExpenseMinor: summary.expenseMinor,
                theme: theme,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 14),

              // Needs vs Wants (刚需 vs 弹性) Card
              _buildNeedsWantsCard(
                summary: summary,
                theme: theme,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 14),

              // Out-of-town & Special Scenario Tags
              _buildOutOfTownCard(
                outOfTownMinor: outOfTownExpenseMinor,
                tagTotals: summary.tagBreakdown,
                theme: theme,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 14),

              // Channel spending distribution
              _buildAccountSpendingCard(
                spendingByAccount: spendingByAccount,
                totalExpenseMinor: summary.expenseMinor,
                theme: theme,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 14),

              // Subcategories Top Ranking
              _buildSubcategoriesCard(
                subTotals: summary.expenseBySubCategory,
                totalExpenseMinor: summary.expenseMinor,
                theme: theme,
                colorScheme: colorScheme,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatColumn({
    required String title,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Text(title, style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildNeedsWantsCard({
    required RichFinanceSummary summary,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final total = summary.needMinor + summary.wantMinor;
    final needPercent = total > 0 ? (summary.needMinor / total * 100) : 50.0;
    final wantPercent = total > 0 ? (summary.wantMinor / total * 100) : 50.0;

    String advice;
    if (total == 0) {
      advice = '本月暂无支出记录，继续保持健康的消费习惯！';
    } else if (wantPercent > 40) {
      final potentialSave = (summary.wantMinor * 0.3 / 100).toStringAsFixed(0);
      advice =
          '本月弹性改善消费占比达到 ${wantPercent.toStringAsFixed(0)}%，稍高于 30% 的合理阈值。'
          '如果适度减少外卖、茶饮和数码可选购物，预计可多存下约 ¥$potentialSave 元！';
    } else {
      advice =
          '本月刚需与弹性消费控制极佳（刚需 ${needPercent.toStringAsFixed(0)}% / 弹性 ${wantPercent.toStringAsFixed(0)}%），财务结构非常健康！';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                Text(
                  '刚需支出 vs 弹性消费',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '消费质量透视',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    Expanded(
                      flex: (needPercent * 10).round().clamp(1, 1000),
                      child: Container(color: Colors.teal),
                    ),
                    Expanded(
                      flex: (wantPercent * 10).round().clamp(1, 1000),
                      child: Container(color: Colors.amber),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 8, height: 8, color: Colors.teal),
                    const SizedBox(width: 4),
                    Text(
                      '刚需必需: ¥${(summary.needMinor / 100).toStringAsFixed(0)} (${needPercent.toStringAsFixed(0)}%)',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 8, height: 8, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      '弹性改善: ¥${(summary.wantMinor / 100).toStringAsFixed(0)} (${wantPercent.toStringAsFixed(0)}%)',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      advice,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
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

  Widget _buildOutOfTownCard({
    required int outOfTownMinor,
    required Map<String, int> tagTotals,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                    Icon(Icons.location_on_outlined,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '异地与专题场景消费',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '异地总额: ¥${(outOfTownMinor / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '通过为账单添加地点或场景标签，清晰核算在外地、出差或探亲时的支出。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (tagTotals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('本月暂无带场景标签的流水，记账时可勾选 #异地消费 或 #差旅出差',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: tagTotals.entries.map((entry) {
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '#${entry.key} ¥${(entry.value / 100).toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor:
                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSpendingCard({
    required Map<String, int> spendingByAccount,
    required int totalExpenseMinor,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final sorted = spendingByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '多渠道支出分布 (从哪扣的钱)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              Text('本月暂无渠道支出记录',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline))
            else
              for (final entry in sorted) ...[
                Builder(
                  builder: (context) {
                    final percent = totalExpenseMinor > 0
                        ? (entry.value / totalExpenseMinor * 100)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(entry.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                '¥${(entry.value / 100).toStringAsFixed(2)} (${percent.toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (percent / 100).clamp(0.0, 1.0),
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubcategoriesCard({
    required Map<String, int> subTotals,
    required int totalExpenseMinor,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final sorted = subTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '细分子类花费排行榜',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              Text('本月暂无细分子类消费',
                  style: TextStyle(fontSize: 12, color: colorScheme.outline))
            else
              for (int i = 0; i < sorted.length && i < 8; i++) ...[
                Builder(
                  builder: (context) {
                    final entry = sorted[i];
                    final percent = totalExpenseMinor > 0
                        ? (entry.value / totalExpenseMinor * 100)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: i < 3
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: i < 3
                                    ? Colors.white
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(entry.key,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(
                            '¥${(entry.value / 100).toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${percent.toStringAsFixed(0)}%',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthOverMonthCard({
    required RichFinanceSummary current,
    required RichFinanceSummary previous,
    required DateTime previousMonthDate,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final diffExpense = current.expenseMinor - previous.expenseMinor;
    final diffIncome = current.incomeMinor - previous.incomeMinor;
    final currentNet = current.incomeMinor - current.expenseMinor;
    final prevNet = previous.incomeMinor - previous.expenseMinor;
    final diffNet = currentNet - prevNet;

    final expensePct = previous.expenseMinor > 0
        ? (diffExpense / previous.expenseMinor * 100)
        : null;
    final incomePct = previous.incomeMinor > 0
        ? (diffIncome / previous.incomeMinor * 100)
        : null;

    final prevMonthStr = DateFormat('M月').format(previousMonthDate);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                    Icon(Icons.compare_arrows_rounded,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '月度环比分析',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '对比 $prevMonthStr',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildComparisonItem(
                    label: '支出变化',
                    diffMinor: diffExpense,
                    pct: expensePct,
                    isExpense: true,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ),
                Container(
                    height: 48,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                Expanded(
                  child: _buildComparisonItem(
                    label: '收入变化',
                    diffMinor: diffIncome,
                    pct: incomePct,
                    isExpense: false,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ),
                Container(
                    height: 48,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                Expanded(
                  child: _buildComparisonItem(
                    label: '结余变化',
                    diffMinor: diffNet,
                    pct: null,
                    isExpense: false,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonItem({
    required String label,
    required int diffMinor,
    required double? pct,
    required bool isExpense,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final isIncrease = diffMinor > 0;
    final isZero = diffMinor == 0;

    Color color;
    if (isZero) {
      color = colorScheme.outline;
    } else if (isExpense) {
      color = isIncrease ? colorScheme.error : Colors.green;
    } else {
      color = isIncrease ? Colors.green : colorScheme.error;
    }

    final sign = isIncrease ? '+' : (diffMinor < 0 ? '-' : '');
    final absAmount = (diffMinor.abs() / 100).toStringAsFixed(2);
    final pctText = pct != null
        ? ' (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)'
        : '';

    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        Text(
          isZero ? '持平' : '$sign¥$absAmount',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
        if (pctText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            pctText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDailyTrendCard({
    required List<FinanceEntry> entries,
    required DateTime selectedMonth,
    required int totalExpenseMinor,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final daysInMonth =
        DateUtils.getDaysInMonth(selectedMonth.year, selectedMonth.month);
    final dailyExpenses = List<int>.filled(daysInMonth + 1, 0);

    for (final e in entries) {
      if (e.direction == FinanceDirection.expense && !e.isReimbursable) {
        final dt = DateTime.fromMillisecondsSinceEpoch(e.occurredAt);
        if (dt.day >= 1 && dt.day <= daysInMonth) {
          dailyExpenses[dt.day] += e.amountMinor;
        }
      }
    }

    int peakDay = 1;
    int peakAmount = 0;
    int activeDays = 0;

    for (int d = 1; d <= daysInMonth; d++) {
      if (dailyExpenses[d] > 0) {
        activeDays++;
        if (dailyExpenses[d] > peakAmount) {
          peakAmount = dailyExpenses[d];
          peakDay = d;
        }
      }
    }

    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;
    final elapsedDays =
        isCurrentMonth ? now.day.clamp(1, daysInMonth) : daysInMonth;
    final avgDaily =
        elapsedDays > 0 ? (totalExpenseMinor / elapsedDays) : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
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
                    Icon(Icons.bar_chart_rounded,
                        size: 20, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '日度支出走势 (全月 $daysInMonth 天)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '消费 $activeDays 天',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatMini(
                  title: '单日峰值',
                  value: peakAmount > 0
                      ? '¥${(peakAmount / 100).toStringAsFixed(1)} ($peakDay日)'
                      : '¥0.00',
                  color: colorScheme.error,
                  theme: theme,
                ),
                Container(
                    height: 24,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                _buildStatMini(
                  title: '日均支出',
                  value: '¥${(avgDaily / 100).toStringAsFixed(1)}',
                  color: colorScheme.primary,
                  theme: theme,
                ),
                Container(
                    height: 24,
                    width: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                _buildStatMini(
                  title: '无消费天数',
                  value: '${daysInMonth - activeDays} 天',
                  color: Colors.green,
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (peakAmount == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '本月暂无支出数据',
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
              )
            else
              SizedBox(
                height: 110,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (int d = 1; d <= daysInMonth; d++) ...[
                        Builder(
                          builder: (context) {
                            final amount = dailyExpenses[d];
                            final barHeightRatio = peakAmount > 0
                                ? (amount / peakAmount).clamp(0.0, 1.0)
                                : 0.0;
                            final isPeak = d == peakDay && peakAmount > 0;
                            final isToday = isCurrentMonth && d == now.day;

                            return Tooltip(
                              message:
                                  '$d日: ¥${(amount / 100).toStringAsFixed(2)}',
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2.5),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (amount > 0)
                                      Text(
                                        (amount / 100).toStringAsFixed(0),
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: isPeak
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isPeak
                                              ? colorScheme.error
                                              : colorScheme.outline,
                                        ),
                                      )
                                    else
                                      const SizedBox(height: 11),
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 14,
                                      height: (barHeightRatio * 64).clamp(
                                          amount > 0 ? 4.0 : 2.0, 64.0),
                                      decoration: BoxDecoration(
                                        color: isPeak
                                            ? colorScheme.error
                                            : amount > 0
                                                ? colorScheme.primary
                                                    .withValues(alpha: 0.75)
                                                : colorScheme
                                                    .surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(3),
                                        border: isToday
                                            ? Border.all(
                                                color: colorScheme.primary,
                                                width: 1.5)
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$d',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isToday
                                            ? colorScheme.primary
                                            : colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatMini({
    required String title,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Text(title, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    );
  }
}
