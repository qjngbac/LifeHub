import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/finance_export_service.dart';
import 'package:lifehub/features/finance/application/finance_preferences.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';
import 'package:lifehub/features/finance/data/subscription_repository.dart';
import 'package:lifehub/features/finance/presentation/accounts_management_page.dart';
import 'package:lifehub/features/finance/presentation/bill_import_preview_page.dart';
import 'package:lifehub/features/finance/presentation/finance_analytics_page.dart';
import 'package:lifehub/features/finance/presentation/reimbursement_list_page.dart';
import 'package:lifehub/features/finance/presentation/subscriptions_page.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});
  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
  int revision = 0;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedAccountId; // null means all accounts
  String? _selectedDirectionFilter; // null means all, 'EXPENSE', 'INCOME', 'TRANSFER'
  String? _selectedCategoryFilter; // null means all categories
  String? _selectedNatureFilter; // null means all natures, 'NEED', 'WANT'
  String _searchQuery = '';
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _accountsScrollController =
      ScrollController(keepScrollOffset: false);

  void _refresh() => setState(() => revision++);

  void _resetAllFilters() {
    setState(() {
      _selectedDirectionFilter = null;
      _selectedCategoryFilter = null;
      _selectedNatureFilter = null;
      _searchQuery = '';
      _searchController.clear();
      _showSearchBar = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _healData();
    });
  }

  Future<void> _healData() async {
    try {
      final db = ref.read(databaseProvider);
      final repo = FinanceRepository(db);
      final c1 = await repo.healMisclassifiedTransfers();
      final c2 = await repo.healCampusAndRepaymentEntries();
      final c3 = await repo.healFoodSubcategories();
      if ((c1 + c2 + c3) > 0 && mounted) {
        _refresh();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _accountsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final database = ref.watch(databaseProvider);
    final repository = FinanceRepository(database);
    final accountRepo = AccountRepository(database);
    final end = DateTime(month.year, month.month + 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('财务收支'),
        actions: [
          IconButton(
            tooltip: '批量导入账单 (CSV / Excel / PDF)',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _pickAndImportCsv,
          ),
          IconButton(
            tooltip: '财务深度分析与洞察',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FinanceAnalyticsPage()),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) async {
              if (val == 'budget') {
                await _openBudgetDialog();
              } else if (val == 'accounts') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountsManagementPage()),
                );
                _refresh();
              } else if (val == 'reimbursement') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReimbursementListPage()),
                );
                _refresh();
              } else if (val == 'subscriptions') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionsPage()),
                );
                _refresh();
              } else if (val == 'export_csv') {
                await _exportCsv();
              } else if (val == 'import_guide') {
                _showImportGuideDialog();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'budget',
                child: Row(
                  children: [
                    Icon(Icons.savings_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('设定月度支出预算'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'import_guide',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 18),
                    SizedBox(width: 8),
                    Text('账单导出教程指引'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'accounts',
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('资金账户与对账'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reimbursement',
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('待报销垫付专区'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'subscriptions',
                child: Row(
                  children: [
                    Icon(Icons.autorenew, size: 18),
                    SizedBox(width: 8),
                    Text('周期订阅管理'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export_csv',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('导出当前月账单 (CSV)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(repository, accountRepo),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: FutureBuilder<List<Object>>(
        key: ValueKey(
            '${month.year}-${month.month}-$_selectedAccountId'),
        future: Future.wait<Object>([
          repository.richMonthlySummary(month.year, month.month),
          repository.list(
            start: month,
            end: end,
            accountId: _selectedAccountId,
          ),
          () async {
            await accountRepo.ensureDefaultAccounts();
            return accountRepo.listAccounts();
          }(),
          SubscriptionRepository(database).list(),
          () async {
            final prefs = await SharedPreferences.getInstance();
            return FinancePreferences(prefs).getMonthlyBudget(month.year, month.month) ?? 0;
          }(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              const Text('财务数据加载失败，请重试'),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _refresh, child: const Text('重试')),
            ]));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data![0] as RichFinanceSummary;
          final entries = snapshot.data![1] as List<FinanceEntry>;
          final accounts = snapshot.data![2] as List<FinanceAccountEntry>;
          final subscriptions = snapshot.data![3] as List<SubscriptionEntry>;
          final budgetMinor = snapshot.data![4] as int;
          final accountMap = {for (final a in accounts) a.id: a};

          final dueSubs = subscriptions.where((s) {
            if (s.status != 'ACTIVE') return false;
            final d = DateKeys.fromLocalDateKey(s.nextRenewalDate);
            return d.year == month.year && d.month == month.month;
          }).toList();

          final sortedCategories = summary.expenseByCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final totalCount = entries.length;
          final expenseCount = entries
              .where((e) => e.direction == FinanceDirection.expense)
              .length;
          final incomeCount = entries
              .where((e) => e.direction == FinanceDirection.income)
              .length;
          final transferCount = entries
              .where((e) => e.direction == FinanceDirection.transfer)
              .length;

          final isFiltered = _selectedDirectionFilter != null ||
              _selectedCategoryFilter != null ||
              _selectedNatureFilter != null ||
              _searchQuery.trim().isNotEmpty;

          final filteredEntries = entries.where((item) {
            if (_selectedDirectionFilter != null &&
                item.direction != _selectedDirectionFilter) {
              return false;
            }
            if (_selectedCategoryFilter != null &&
                item.category != _selectedCategoryFilter) {
              return false;
            }
            if (_selectedNatureFilter != null &&
                item.expenseNature != _selectedNatureFilter) {
              return false;
            }
            if (_searchQuery.trim().isNotEmpty) {
              final q = _searchQuery.trim().toLowerCase();
              final note = (item.note ?? '').toLowerCase();
              final cat = item.category.toLowerCase();
              final sub = (item.subCategory ?? '').toLowerCase();
              final tags = (item.tagsJson ?? '').toLowerCase();
              final catName =
                  FinanceCategoryCatalog.label(item.category).toLowerCase();
              if (!note.contains(q) &&
                  !cat.contains(q) &&
                  !sub.contains(q) &&
                  !tags.contains(q) &&
                  !catName.contains(q)) {
                return false;
              }
            }
            return true;
          }).toList();

          return ListView(
            key: const PageStorageKey<String>('finance_entries_list'),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              // 1. Multi-account Balance Carousel
              _buildAccountsBar(accounts, accountRepo, colorScheme, theme),
              const SizedBox(height: 10),

              // Due Subscriptions Reminder
              if (dueSubs.isNotEmpty) ...[
                _buildDueSubscriptionsCard(dueSubs, colorScheme, theme),
                const SizedBox(height: 10),
              ],

              // 2. Month Selector Row
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                        () => month = DateTime(month.year, month.month - 1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${month.year}年${month.month}月',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                        () => month = DateTime(month.year, month.month + 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Macro & Micro Monthly Summary Card
              Card(
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
                    children: [
                      Align(alignment: Alignment.centerLeft,
                        child: Text('全账户 · 本月汇总', style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline))),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                if (_selectedDirectionFilter == FinanceDirection.income) {
                                  _selectedDirectionFilter = null;
                                } else {
                                  _selectedDirectionFilter = FinanceDirection.income;
                                }
                              });
                            },
                            child: _amount(
                              '总收入',
                              summary.incomeMinor,
                              Colors.green,
                              isSelected: _selectedDirectionFilter == FinanceDirection.income,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                if (_selectedDirectionFilter == FinanceDirection.expense) {
                                  _selectedDirectionFilter = null;
                                } else {
                                  _selectedDirectionFilter = FinanceDirection.expense;
                                }
                              });
                            },
                            child: _amount(
                              '净支出',
                              summary.expenseMinor,
                              Colors.deepOrange,
                              isSelected: _selectedDirectionFilter == FinanceDirection.expense,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              _resetAllFilters();
                            },
                            child: _amount(
                              '结余差额',
                              summary.netMinor,
                              summary.netMinor >= 0 ? colorScheme.primary : colorScheme.error,
                              isSelected: _selectedDirectionFilter == null && !isFiltered,
                            ),
                          ),
                        ],
                      ),

                      // Pending Reimbursement Banner
                      if (summary.pendingReimburseMinor > 0) ...[
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ReimbursementListPage()),
                            );
                            _refresh();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: colorScheme.tertiary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '本月垫付 ¥${(summary.pendingReimburseMinor / 100).toStringAsFixed(2)} 待收回 (未计入净支出)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.tertiary,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 16, color: colorScheme.tertiary),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Needs vs Wants split bar
                      if (summary.expenseMinor > 0) ...[
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '消费性质分层',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                            Text(
                              '刚需 ${(summary.needRatio * 100).toStringAsFixed(0)}% · 弹性 ${(summary.wantRatio * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (summary.needRatio * 1000).round(),
                                child: Container(
                                  height: 8,
                                  color: Colors.blue[600],
                                ),
                              ),
                              Expanded(
                                flex: (summary.wantRatio * 1000).round(),
                                child: Container(
                                  height: 8,
                                  color: Colors.orange[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '刚需生活必需: ¥${(summary.needMinor / 100).toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.blue[700]),
                            ),
                            Text(
                              '弹性改善可选: ¥${(summary.wantMinor / 100).toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange[800]),
                            ),
                          ],
                        ),
                      ],

                      // Top Categories Breakdown
                      if (summary.expenseMinor > 0 &&
                          sortedCategories.isNotEmpty) ...[
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '支出大项与二级分类细分',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...sortedCategories.take(4).map((entry) {
                          final ratio = entry.value / summary.expenseMinor;
                          final catDef =
                              FinanceCategoryCatalog.getExpense(entry.key);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(catDef.icon,
                                            size: 14, color: catDef.color),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${catDef.name} ${(ratio * 100).toStringAsFixed(1)}%',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '¥${(entry.value / 100).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: ratio.clamp(0.0, 1.0),
                                    minHeight: 5,
                                    color: catDef.color,
                                    backgroundColor: colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
              // Monthly Budget Section
              _buildBudgetSection(
                expenseMinor: summary.expenseMinor,
                budgetMinor: budgetMinor,
                colorScheme: colorScheme,
                theme: theme,
              ),

              const SizedBox(height: 12),
              // Stream Filter Bar & Section Header
              _buildStreamFilterBar(
                context: context,
                theme: theme,
                colorScheme: colorScheme,
                totalCount: totalCount,
                expenseCount: expenseCount,
                incomeCount: incomeCount,
                transferCount: transferCount,
                filteredCount: filteredEntries.length,
                isFiltered: isFiltered,
                accountMap: accountMap,
                allEntries: entries,
              ),
              const SizedBox(height: 8),

              if (entries.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: Text('本月暂无记录，轻触右下角「记一笔」添加'),
                    ),
                  ),
                )
              else if (filteredEntries.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.filter_alt_off_outlined,
                            size: 36, color: colorScheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          '未找到符合当前筛选条件的账单',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: _resetAllFilters,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重置所有筛选'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._buildDailyGroupedEntries(
                  filteredEntries,
                  accountMap,
                  repository,
                  colorScheme,
                  theme,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountsBar(
    List<FinanceAccountEntry> accounts,
    AccountRepository accountRepo,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return SizedBox(
      height: 40,
      child: ListView(
        key: const PageStorageKey<String>('finance_accounts_bar_isolated'),
        controller: _accountsScrollController,
        primary: false,
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            selected: _selectedAccountId == null,
            label: const Text('全部账户'),
            onSelected: (_) => setState(() => _selectedAccountId = null),
          ),
          const SizedBox(width: 8),
          for (final acc in accounts) ...[
            GestureDetector(
              onLongPress: () => _openAdjustBalanceDialog(accountRepo, acc),
              child: FilterChip(
                tooltip: '轻触筛选该账户，长按快捷校准余额',
                selected: _selectedAccountId == acc.id,
                avatar: CircleAvatar(
                  radius: 6,
                  backgroundColor: Color(int.parse(
                      '0xFF${acc.color.replaceFirst('#', '').padRight(6, '0')}')),
                ),
                label: Text(
                  '${acc.name} ¥${(acc.balanceMinor / 100).toStringAsFixed(2)}',
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedAccountId = selected ? acc.id : null;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDueSubscriptionsCard(
    List<SubscriptionEntry> dueSubs,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    int dueTotal = 0;
    for (final s in dueSubs) {
      dueTotal += s.amountMinor;
    }
    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.autorenew, color: colorScheme.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本月有 ${dueSubs.length} 笔周期支出待确认（共 ¥${(dueTotal / 100).toStringAsFixed(2)}）',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    dueSubs.map((s) => s.name).take(3).join('、'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SubscriptionsPage()),
                );
                _refresh();
              },
              child: const Text('管理/扣费'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndImportCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      List<int>? rawBytes = file.bytes;
      if (rawBytes == null && file.path != null) {
        final ioFile = File(file.path!);
        if (await ioFile.exists()) {
          rawBytes = await ioFile.readAsBytes();
        }
      }

      if (rawBytes == null || rawBytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未能读取到所选文件内容，请重新选择')),
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final customRules = FinancePreferences(prefs).getMerchantRules();
      final items = BillCsvParser.parseBytes(rawBytes,
          fileName: file.name, customRules: customRules);
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(
                '未能在文件（${file.name}）中识别到有效账单流水。\n请确认是微信、支付宝或银行官方导出的对账单（支持 CSV / Excel / PDF）。',
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final imported = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BillImportPreviewPage(rawItems: items),
        ),
      );
      if (imported == true) {
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入异常: $e')),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    try {
      final db = ref.read(databaseProvider);
      final exportService = FinanceExportService(db);
      final bytes = await exportService.exportToCsvBytes(month: month);

      final monthStr = DateFormat('yyyy_MM').format(month);
      final defaultName = 'LifeHub_账单_$monthStr.csv';

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出当前月份账单 CSV',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );

      if (outputPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('账单已成功导出至: $outputPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  static bool _isRewardNote(String? note) {
    if (note == null || note.isEmpty) return false;
    return note.contains('68元') ||
        note.contains('活动') ||
        note.contains('奖励') ||
        note.contains('领现金') ||
        note.contains('羊毛') ||
        note.contains('补贴') ||
        note.contains('金币') ||
        note.contains('百度') ||
        note.contains('小说') ||
        note.contains('音乐') ||
        note.contains('剧场') ||
        note.contains('转到零钱') ||
        note.contains('收益');
  }

  static String _cleanTitleText(String text) {
    var t = text.replaceAll(RegExp(r'\[单号:\s*[^\]]+\]'), '').trim();
    t = t.replaceAll(RegExp(r'\s*[-/]\s*/\s*$'), '').trim();
    t = t.replaceAll(RegExp(r'\s*-\s*$'), '').trim();
    t = t.replaceAll(RegExp(r'^\s*[-/]\s*'), '').trim();

    if (t.contains(' - ')) {
      final parts = t
          .split(' - ')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length == 2) {
        final p0 = parts[0];
        final p1 = parts[1];
        if (p1 == '/' ||
            p1.contains('转账备注') ||
            p1 == '微信转账' ||
            p1 == '转账') {
          t = p0;
        } else if (p1.startsWith(p0)) {
          t = p1;
        } else if (p0.startsWith(p1)) {
          t = p0;
        } else if (p1.contains(p0)) {
          t = p1;
        } else if (p0 == p1) {
          t = p0;
        }
      }
    }
    return t;
  }

  String _getCleanDisplayTitle(
    FinanceEntry item,
    CategoryDef catDef,
    FinanceAccountEntry? sourceAccount,
    FinanceAccountEntry? targetAccount,
  ) {
    final isMisclassifiedReward = item.direction == FinanceDirection.transfer &&
        item.targetAccountId == null &&
        _isRewardNote(item.note);

    if (item.direction == FinanceDirection.transfer && !isMisclassifiedReward) {
      if (sourceAccount != null && targetAccount != null) {
        return '${sourceAccount.name} ➔ ${targetAccount.name}';
      }
      if (sourceAccount != null) {
        final rawNote = item.note ?? '';
        final cleanNote = _cleanTitleText(rawNote);
        if (cleanNote.contains('银行') || cleanNote.contains('储蓄卡')) {
          return '${sourceAccount.name} ➔ $cleanNote';
        }
        if (cleanNote.isNotEmpty && cleanNote != '/') {
          return cleanNote;
        }
        return item.subCategory?.isNotEmpty == true
            ? '${item.subCategory!} · ${sourceAccount.name}'
            : '${sourceAccount.name} 转账';
      }
      return item.subCategory ?? '内部转账';
    }

    var text = _cleanTitleText(item.note ?? '');
    if (text.isEmpty) {
      return item.subCategory?.isNotEmpty == true
          ? item.subCategory!
          : catDef.name;
    }
    return text;
  }

  Widget _buildEntryCard(
    FinanceEntry item,
    Map<String, FinanceAccountEntry> accountMap,
    FinanceRepository repository,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isMisclassifiedReward = item.direction == FinanceDirection.transfer &&
        item.targetAccountId == null &&
        _isRewardNote(item.note);

    final isIncome =
        item.direction == FinanceDirection.income || isMisclassifiedReward;
    final isTransfer =
        item.direction == FinanceDirection.transfer && !isMisclassifiedReward;
    final isReimbursablePending =
        item.isReimbursable && item.reimburseStatus == 'UNPAID';

    final sourceAccount =
        item.accountId != null ? accountMap[item.accountId] : null;
    final targetAccount =
        item.targetAccountId != null ? accountMap[item.targetAccountId] : null;

    final catDef = isIncome
        ? FinanceCategoryCatalog.getIncome(
            isMisclassifiedReward ? 'SIDE_INCOME' : item.category)
        : FinanceCategoryCatalog.getExpense(item.category);

    final titleText = _getCleanDisplayTitle(
      item,
      catDef,
      sourceAccount,
      targetAccount,
    );

    final displaySubCategory = isMisclassifiedReward
        ? '活动奖励'
        : (item.subCategory?.isNotEmpty == true ? item.subCategory! : null);

    final dateStr = DateFormat('M月d日')
        .format(DateTime.fromMillisecondsSinceEpoch(item.occurredAt));

    final cardWidget = Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isReimbursablePending
              ? colorScheme.tertiary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(repository, item, accountMap),
        onLongPress: () => _showEntryActionSheet(item, repository, accountMap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Leading Icon Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isTransfer
                      ? Colors.purple.withValues(alpha: 0.12)
                      : (isIncome
                          ? Colors.green.withValues(alpha: 0.12)
                          : catDef.color.withValues(alpha: 0.12)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isTransfer
                      ? Icons.swap_horiz_rounded
                      : (isIncome
                          ? (catDef.id == 'OTHER_INCOME'
                              ? Icons.account_balance_wallet_rounded
                              : catDef.icon)
                          : catDef.icon),
                  color: isTransfer
                      ? Colors.purple
                      : (isIncome ? Colors.green[700] : catDef.color),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // 2. Middle Expanded Content (Title + Subtitle)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            titleText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isReimbursablePending) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '待报销',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                        if (!isTransfer && !isIncome) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: item.expenseNature == ExpenseNature.want
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.expenseNature == ExpenseNature.want
                                  ? '弹性'
                                  : '刚需',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: item.expenseNature == ExpenseNature.want
                                    ? Colors.orange[800]
                                    : Colors.blue[800],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      runSpacing: 2,
                      children: [
                        Text(
                          dateStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                        if (!isTransfer) ...[
                          Text(
                            '·',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          Text(
                            catDef.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                        if (displaySubCategory != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              displaySubCategory,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (sourceAccount != null && !isTransfer) ...[
                          Text(
                            '·',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          Text(
                            sourceAccount.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // 3. Right Column (Amount + 3-dots Menu)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isTransfer
                        ? '¥${(item.amountMinor / 100).toStringAsFixed(2)}'
                        : '${isIncome ? '+' : '-'}¥${(item.amountMinor / 100).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isTransfer
                          ? Colors.purple
                          : (isIncome
                              ? Colors.green[700]
                              : (isReimbursablePending
                                  ? Colors.grey
                                  : colorScheme.onSurface)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: colorScheme.outline,
                      ),
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await _addOrEdit(
                            repository,
                            AccountRepository(ref.read(databaseProvider)),
                            existing: item,
                          );
                        } else if (action == 'delete') {
                          await _delete(repository, item);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('编辑'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
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
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss_entry_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('删除',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(width: 4),
            Icon(Icons.delete_outline, color: Colors.white, size: 20),
          ],
        ),
      ),
      confirmDismiss: (dir) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认删除该账单？'),
            content: Text(
                '删除后该笔记录（¥${(item.amountMinor / 100).toStringAsFixed(2)}）将无法恢复。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        await repository.delete(item.id);
        _refresh();
      },
      child: cardWidget,
    );
  }

  Widget _buildStreamFilterBar({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required int totalCount,
    required int expenseCount,
    required int incomeCount,
    required int transferCount,
    required int filteredCount,
    required bool isFiltered,
    required Map<String, FinanceAccountEntry> accountMap,
    required List<FinanceEntry> allEntries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  _selectedAccountId != null
                      ? '「${accountMap[_selectedAccountId]?.name ?? '该账户'}」流水'
                      : '账单流水明细',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isFiltered
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isFiltered ? '$filteredCount / $totalCount 笔' : '$totalCount 笔',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isFiltered
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFiltered)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _resetAllFilters,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('重置筛选', style: TextStyle(fontSize: 12)),
                  ),
                if (_selectedAccountId != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => setState(() => _selectedAccountId = null),
                    child: const Text('全部账户', style: TextStyle(fontSize: 12)),
                  ),
                IconButton(
                  tooltip: _showSearchBar ? '收起搜索' : '展开搜索',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _showSearchBar || _searchQuery.isNotEmpty
                        ? Icons.search
                        : Icons.search_outlined,
                    color: _searchQuery.isNotEmpty ? colorScheme.primary : null,
                  ),
                  onPressed: () {
                    setState(() {
                      _showSearchBar = !_showSearchBar;
                      if (!_showSearchBar && _searchQuery.isNotEmpty) {
                        _searchQuery = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),

        // Search Bar (expandable)
        if (_showSearchBar || _searchQuery.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索商户、分类、子分类或备注...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ],
        const SizedBox(height: 8),

        // Direction Selector (全部 / 支出 / 收入 / 内部互转)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDirectionTab(
                label: '全部',
                count: totalCount,
                isSelected: _selectedDirectionFilter == null,
                colorScheme: colorScheme,
                onTap: () => setState(() {
                  _selectedDirectionFilter = null;
                  _selectedCategoryFilter = null;
                }),
              ),
              const SizedBox(width: 6),
              _buildDirectionTab(
                label: '支出',
                count: expenseCount,
                isSelected: _selectedDirectionFilter == FinanceDirection.expense,
                colorScheme: colorScheme,
                color: Colors.deepOrange,
                icon: Icons.arrow_upward_rounded,
                onTap: () => setState(() {
                  _selectedDirectionFilter =
                      _selectedDirectionFilter == FinanceDirection.expense
                          ? null
                          : FinanceDirection.expense;
                  _selectedCategoryFilter = null;
                }),
              ),
              const SizedBox(width: 6),
              _buildDirectionTab(
                label: '收入',
                count: incomeCount,
                isSelected: _selectedDirectionFilter == FinanceDirection.income,
                colorScheme: colorScheme,
                color: Colors.green,
                icon: Icons.arrow_downward_rounded,
                onTap: () => setState(() {
                  _selectedDirectionFilter =
                      _selectedDirectionFilter == FinanceDirection.income
                          ? null
                          : FinanceDirection.income;
                  _selectedCategoryFilter = null;
                }),
              ),
              const SizedBox(width: 6),
              _buildDirectionTab(
                label: '转账',
                count: transferCount,
                isSelected: _selectedDirectionFilter == FinanceDirection.transfer,
                colorScheme: colorScheme,
                color: Colors.purple,
                icon: Icons.swap_horiz_rounded,
                onTap: () => setState(() {
                  _selectedDirectionFilter =
                      _selectedDirectionFilter == FinanceDirection.transfer
                          ? null
                          : FinanceDirection.transfer;
                  _selectedCategoryFilter = null;
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // Secondary Filters: Category & Nature Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Category Filter Chip
              FilterChip(
                visualDensity: VisualDensity.compact,
                selected: _selectedCategoryFilter != null,
                avatar: Icon(
                  _selectedCategoryFilter != null
                      ? FinanceCategoryCatalog.getDef(
                              _selectedCategoryFilter!, _selectedDirectionFilter)
                          .icon
                      : Icons.category_outlined,
                  size: 14,
                  color: _selectedCategoryFilter != null
                      ? FinanceCategoryCatalog.getDef(
                              _selectedCategoryFilter!, _selectedDirectionFilter)
                          .color
                      : colorScheme.outline,
                ),
                label: Text(
                  _selectedCategoryFilter != null
                      ? FinanceCategoryCatalog.label(_selectedCategoryFilter!)
                      : '全部分类',
                  style: const TextStyle(fontSize: 12),
                ),
                onSelected: (_) {
                  _showCategoryFilterSheet(context, allEntries);
                },
              ),
              const SizedBox(width: 6),

              // Nature Filter Chip (only shown when not filtering strictly income or transfer)
              if (_selectedDirectionFilter != FinanceDirection.income &&
                  _selectedDirectionFilter != FinanceDirection.transfer) ...[
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  selected: _selectedNatureFilter != null,
                  avatar: Icon(
                    _selectedNatureFilter == ExpenseNature.need
                        ? Icons.check_circle_outline
                        : (_selectedNatureFilter == ExpenseNature.want
                            ? Icons.star_outline
                            : Icons.tune),
                    size: 14,
                    color: _selectedNatureFilter == ExpenseNature.need
                        ? Colors.blue[700]
                        : (_selectedNatureFilter == ExpenseNature.want
                            ? Colors.orange[800]
                            : colorScheme.outline),
                  ),
                  label: Text(
                    _selectedNatureFilter == ExpenseNature.need
                        ? '刚需必需'
                        : (_selectedNatureFilter == ExpenseNature.want
                            ? '弹性改善'
                            : '全部性质'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onSelected: (_) {
                    setState(() {
                      if (_selectedNatureFilter == null) {
                        _selectedNatureFilter = ExpenseNature.need;
                      } else if (_selectedNatureFilter == ExpenseNature.need) {
                        _selectedNatureFilter = ExpenseNature.want;
                      } else {
                        _selectedNatureFilter = null;
                      }
                    });
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionTab({
    required String label,
    required int count,
    required bool isSelected,
    required ColorScheme colorScheme,
    Color? color,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    final activeColor = color ?? colorScheme.primary;
    return Material(
      color: isSelected
          ? activeColor.withValues(alpha: 0.15)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? activeColor : colorScheme.outline,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? activeColor : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? activeColor : colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryFilterSheet(BuildContext context, List<FinanceEntry> allEntries) {
    final relevantEntries = _selectedDirectionFilter != null
        ? allEntries.where((e) => e.direction == _selectedDirectionFilter).toList()
        : allEntries;

    final categoryCounts = <String, int>{};
    for (final e in relevantEntries) {
      categoryCounts[e.category] = (categoryCounts[e.category] ?? 0) + 1;
    }

    final sortedCategories = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colorScheme = theme.colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '按分类筛选流水',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_selectedCategoryFilter != null)
                        TextButton(
                          onPressed: () {
                            setState(() => _selectedCategoryFilter = null);
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('清除分类筛选'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          tileColor: _selectedCategoryFilter == null
                              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                              : null,
                          leading: const Icon(Icons.all_inclusive),
                          title: const Text('全部分类'),
                          trailing: Text('${relevantEntries.length} 笔'),
                          selected: _selectedCategoryFilter == null,
                          onTap: () {
                            setState(() => _selectedCategoryFilter = null);
                            Navigator.pop(sheetContext);
                          },
                        ),
                        const Divider(height: 8),
                        for (final entry in sortedCategories) ...[
                          Builder(builder: (_) {
                            final catDef = FinanceCategoryCatalog.getDef(
                                entry.key, _selectedDirectionFilter);
                            final isSelected = _selectedCategoryFilter == entry.key;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              tileColor: isSelected
                                  ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                                  : null,
                              leading: Icon(catDef.icon, color: catDef.color),
                              title: Text(catDef.name),
                              trailing: Text(
                                '${entry.value} 笔',
                                style: TextStyle(
                                  color: colorScheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSelected,
                              onTap: () {
                                setState(() {
                                  _selectedCategoryFilter = entry.key;
                                });
                                Navigator.pop(sheetContext);
                              },
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _amount(String label, int value, Color color, {bool isSelected = false}) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.5), width: 1.5)
              : Border.all(color: Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color : null,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.check_circle, size: 12, color: color),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '¥${(value / 100).toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );

  Future<void> _openDetail(FinanceRepository repository, FinanceEntry value,
      Map<String, FinanceAccountEntry> accountMap) async {
    final isMisclassifiedReward = value.direction == FinanceDirection.transfer &&
        value.targetAccountId == null &&
        _isRewardNote(value.note);
    final isIncome = value.direction == FinanceDirection.income || isMisclassifiedReward;
    final isTransfer = value.direction == FinanceDirection.transfer && !isMisclassifiedReward;
    final catName = isMisclassifiedReward
        ? '副业兼职 · 活动奖励'
        : FinanceCategoryCatalog.getCategoryName(value.category, value.direction);
    final sourceAcc = value.accountId != null ? accountMap[value.accountId] : null;
    final targetAcc =
        value.targetAccountId != null ? accountMap[value.targetAccountId] : null;

    final cleanTitle = _cleanTitleText(value.note ?? '');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(cleanTitle.isNotEmpty ? cleanTitle : '账单详情'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                onPressed: () async {
                  Navigator.pop(context);
                  await _addOrEdit(repository, AccountRepository(ref.read(databaseProvider)),
                      existing: value);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: () async {
                  Navigator.pop(context);
                  await _delete(repository, value);
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
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
                          Text(catName,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            isTransfer
                                ? '¥${(value.amountMinor / 100).toStringAsFixed(2)}'
                                : '${isIncome ? '+' : '-'}¥${(value.amountMinor / 100).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isTransfer
                                  ? Colors.purple
                                  : (isIncome ? Colors.green[700] : null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      if (isTransfer) ...[
                        Text('转出账户: ${sourceAcc?.name ?? '未指定'}'),
                        const SizedBox(height: 4),
                        Text('转入账户: ${targetAcc?.name ?? '未指定'}'),
                        const SizedBox(height: 4),
                      ] else ...[
                        Text('支付/收款账户: ${sourceAcc?.name ?? '微信钱包'}'),
                        const SizedBox(height: 4),
                        if (isMisclassifiedReward || value.subCategory?.isNotEmpty == true)
                          Text('二级子分类: ${isMisclassifiedReward ? '活动奖励' : value.subCategory}'),
                        if (!isIncome) ...[
                          const SizedBox(height: 4),
                          Text('消费性质: ${value.expenseNature == ExpenseNature.want ? '弹性改善可选' : '刚需生活必需'}'),
                          if (value.isReimbursable)
                            Text('待报销状态: ${value.reimburseStatus == 'UNPAID' ? '未报销' : '已报销平账'}',
                                style: TextStyle(color: Colors.orange[800])),
                        ],
                      ],

                      const SizedBox(height: 4),
                      Text(
                        '发生时间: ${DateFormat('yyyy年M月d日 HH:mm').format(DateTime.fromMillisecondsSinceEpoch(value.occurredAt))}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (value.note?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text('备注说明: ${cleanTitle.isNotEmpty ? cleanTitle : value.note}'),
                      ],
                    ],
                  ),
                ),
              ),
              EntityRelationsPanel(
                  entity: EntityReference(type: 'FINANCE', id: value.id)),
              AttachmentPanel(
                  entityType: 'FINANCE',
                  entityId: value.id,
                  sensitive: value.sensitive),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(
      FinanceRepository repository, FinanceEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账单'),
        content: Text(
            '确定要删除这笔「${entry.note?.isNotEmpty == true ? entry.note : entry.category}」¥${(entry.amountMinor / 100).toStringAsFixed(2)} 记录吗？相关账户余额将自动回退。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirm == true) {
      await repository.delete(entry.id);
      if (mounted) _refresh();
    }
  }

  Future<void> _addOrEdit(
    FinanceRepository repository,
    AccountRepository accountRepo, {
    FinanceEntry? existing,
  }) async {
    final accounts = await accountRepo.listAccounts();
    void increaseAmount(TextEditingController controller, int deltaMinor) {
      try {
        final value = controller.text.trim();
        final current = value.isEmpty || double.tryParse(value) == 0
            ? 0
            : FinanceRepository.parseMinor(value);
        controller.text = ((current + deltaMinor) / 100).toStringAsFixed(2);
      } on ArgumentError {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前金额或算式无效，请先检查输入')),
          );
        }
      }
    }

    var direction = existing?.direction ?? FinanceDirection.expense;
    var category = existing?.category ??
        (direction == FinanceDirection.expense
            ? 'FOOD'
            : (direction == FinanceDirection.income ? 'SALARY' : 'TRANSFER'));

    var subCategory = existing?.subCategory;
    var accountId = existing?.accountId ??
        (accounts.isNotEmpty ? accounts.first.id : null);
    var targetAccountId = existing?.targetAccountId ??
        (accounts.length > 1 ? accounts[1].id : null);
    var expenseNature = existing?.expenseNature ?? ExpenseNature.need;
    var isReimbursable = existing?.isReimbursable ?? false;

    List<String> selectedTags = [];
    if (existing?.tagsJson != null && existing!.tagsJson!.isNotEmpty) {
      try {
        selectedTags = (jsonDecode(existing.tagsJson!) as List)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    var occurredAt = existing != null
        ? DateTime.fromMillisecondsSinceEpoch(existing.occurredAt)
        : DateTime.now();

    final amountCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountMinor / 100).toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    if (!mounted) return;

    final entryRoute = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final now = DateTime.now();
          final isToday = occurredAt.year == now.year &&
              occurredAt.month == now.month &&
              occurredAt.day == now.day;
          final yesterday = now.subtract(const Duration(days: 1));
          final isYesterday = occurredAt.year == yesterday.year &&
              occurredAt.month == yesterday.month &&
              occurredAt.day == yesterday.day;

          // Available categories depending on direction
          final availableCategories = direction == FinanceDirection.income
              ? FinanceCategoryCatalog.incomeCategories
              : FinanceCategoryCatalog.expenseCategories;

          final currentCatDef = direction == FinanceDirection.income
              ? FinanceCategoryCatalog.getIncome(category)
              : FinanceCategoryCatalog.getExpense(category);

          final subcategories = direction == FinanceDirection.transfer
              ? FinanceCategoryCatalog.transferSubcategories
              : currentCatDef.subcategories;

          Widget buildModalItem({
            required String label,
            required bool isSelected,
            required VoidCallback onTap,
            double? width,
            double height = 36,
            double fontSize = 12,
          }) {
            final cs = Theme.of(context).colorScheme;
            return SizedBox(
              width: width,
              height: height,
              child: Material(
                color: isSelected ? cs.primaryContainer : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.6)
                        : cs.outlineVariant.withValues(alpha: 0.8),
                    width: 1.0,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return KeyboardSafeFormDialog(
            title: Text(existing == null ? '快速记一笔' : '编辑账单'),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Direction Segment: Expense, Income, Transfer (Clean text without icons or checkmarks)
                Center(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: FinanceDirection.expense,
                        label: Text('支出'),
                      ),
                      ButtonSegment(
                        value: FinanceDirection.income,
                        label: Text('收入'),
                      ),
                      ButtonSegment(
                        value: FinanceDirection.transfer,
                        label: Text('转账/提现'),
                      ),
                    ],
                    selected: {direction},
                    onSelectionChanged: (values) => setDialogState(() {
                      direction = values.first;
                      if (direction == FinanceDirection.expense) {
                        category = 'FOOD';
                        subCategory = FinanceCategoryCatalog.getExpense('FOOD').subcategories.first;
                      } else if (direction == FinanceDirection.income) {
                        category = 'SALARY';
                        subCategory = FinanceCategoryCatalog.getIncome('SALARY').subcategories.first;
                      } else {
                        category = 'TRANSFER';
                        subCategory = FinanceCategoryCatalog.transferSubcategories.first;
                      }
                    }),
                  ),
                ),
                const SizedBox(height: 12),

                // Amount input with math support
                TextField(
                  controller: amountCtrl,
                  autofocus: existing == null,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: false),
                  decoration: InputDecoration(
                    labelText: '金额 (支持 25+15 算式输入) *',
                    prefixText: '¥ ',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            increaseAmount(amountCtrl, 1000);
                          },
                          child: const Text('+10'),
                        ),
                        TextButton(
                          onPressed: () {
                            increaseAmount(amountCtrl, 5000);
                          },
                          child: const Text('+50'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Account Selection
                if (direction == FinanceDirection.transfer) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('from_acc_$accountId'),
                          initialValue: accountId,
                          decoration: const InputDecoration(labelText: '转出账户'),
                          items: accounts
                              .map((a) => DropdownMenuItem(
                                  value: a.id, child: Text(a.name)))
                              .toList(),
                          onChanged: (val) =>
                              setDialogState(() => accountId = val),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 20),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('to_acc_$targetAccountId'),
                          initialValue: targetAccountId,
                          decoration: const InputDecoration(labelText: '转入账户'),
                          items: accounts
                              .map((a) => DropdownMenuItem(
                                  value: a.id, child: Text(a.name)))
                              .toList(),
                          onChanged: (val) =>
                              setDialogState(() => targetAccountId = val),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('acc_$accountId'),
                    initialValue: accountId,
                    decoration: InputDecoration(
                      labelText: direction == FinanceDirection.income
                          ? '收款账户'
                          : '扣款账户',
                    ),
                    items: accounts
                        .map((a) => DropdownMenuItem(
                            value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (val) => setDialogState(() => accountId = val),
                  ),
                ],
                const SizedBox(height: 10),

                // Primary Category
                if (direction != FinanceDirection.transfer) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('cat_${direction}_$category'),
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '主分类'),
                    items: availableCategories
                        .map((cat) => DropdownMenuItem(
                              value: cat.id,
                              child: Row(
                                children: [
                                  Icon(cat.icon, size: 18, color: cat.color),
                                  const SizedBox(width: 8),
                                  Text(cat.name),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (val) => setDialogState(() {
                      if (val != null) {
                        category = val;
                        final c = direction == FinanceDirection.income
                            ? FinanceCategoryCatalog.getIncome(category)
                            : FinanceCategoryCatalog.getExpense(category);
                        subCategory = c.subcategories.isNotEmpty
                            ? c.subcategories.first
                            : null;
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                ],

                // Subcategory Selection Chips (3 columns grid, no checkmark, purple highlight)
                if (subcategories.isNotEmpty) ...[
                  const Text('细分子类: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = (constraints.maxWidth - 16) / 3;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: subcategories.map((sub) {
                          final isSelected = subCategory == sub;
                          return buildModalItem(
                            label: sub,
                            width: itemWidth,
                            isSelected: isSelected,
                            onTap: () => setDialogState(() => subCategory = sub),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // Needs vs Wants (Single row, 2 equal columns, no checkmark)
                if (direction == FinanceDirection.expense) ...[
                  Row(
                    children: [
                      const Text('消费性质: ', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: buildModalItem(
                          label: '刚需必需',
                          isSelected: expenseNature == ExpenseNature.need,
                          onTap: () => setDialogState(
                              () => expenseNature = ExpenseNature.need),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: buildModalItem(
                          label: '弹性改善',
                          isSelected: expenseNature == ExpenseNature.want,
                          onTap: () => setDialogState(
                              () => expenseNature = ExpenseNature.want),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    title: const Text('替人垫付 / 待公司报销 (不计入生活消费)'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: isReimbursable,
                    onChanged: (val) =>
                        setDialogState(() => isReimbursable = val ?? false),
                  ),
                  const SizedBox(height: 6),
                ],

                // Scene / Location Tags (3 columns grid, no checkmark, purple highlight)
                if (direction == FinanceDirection.expense) ...[
                  const Text('场景标签 (支持多选): ',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = (constraints.maxWidth - 16) / 3;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: FinanceCategoryCatalog.commonSceneTags.map((tag) {
                          final isSelected = selectedTags.contains(tag);
                          return buildModalItem(
                            label: '#$tag',
                            width: itemWidth,
                            fontSize: 11,
                            isSelected: isSelected,
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  selectedTags.remove(tag);
                                } else {
                                  selectedTags.add(tag);
                                }
                              });
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                // Date Selector Chips (No checkmark, purple highlight)
                Row(
                  children: [
                    const Text('日期: ', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    buildModalItem(
                      label: '今天',
                      width: 66,
                      isSelected: isToday,
                      onTap: () =>
                          setDialogState(() => occurredAt = DateTime.now()),
                    ),
                    const SizedBox(width: 6),
                    buildModalItem(
                      label: '昨天',
                      width: 66,
                      isSelected: isYesterday,
                      onTap: () => setDialogState(() => occurredAt =
                          DateTime.now().subtract(const Duration(days: 1))),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      height: 36,
                      child: Material(
                        color: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.8),
                            width: 1.0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: occurredAt,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => occurredAt = picked);
                            }
                          },
                          child: const Center(
                            child:
                                Icon(Icons.calendar_month_outlined, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: '商户、地点或备注',
                    hintText: '如 商户名称、地点或备注信息',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存入账'),
              ),
            ],
          );
        },
      ),
    );

    final save = await Navigator.of(context, rootNavigator: true).push(entryRoute);
    await entryRoute.completed;
    if (save == true && amountCtrl.text.trim().isNotEmpty) {
      final amountMinor = FinanceRepository.parseMinor(amountCtrl.text);
      final draft = FinanceDraft(
        direction: direction,
        amountMinor: amountMinor,
        category: category,
        subCategory: subCategory,
        accountId: accountId,
        targetAccountId: direction == FinanceDirection.transfer ? targetAccountId : null,
        expenseNature: expenseNature,
        isReimbursable: isReimbursable,
        tags: selectedTags,
        occurredAt: occurredAt,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );

      if (existing != null) {
        await repository.update(existing.id, draft);
      } else {
        await repository.create(draft);
      }
      final noteText = noteCtrl.text.trim();
      if (noteText.isNotEmpty && direction != FinanceDirection.transfer) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await FinancePreferences(prefs).saveMerchantRule(
            noteText,
            category: category,
            subCategory: subCategory,
            expenseNature: expenseNature,
          );
        } catch (_) {}
      }
      if (mounted) _refresh();
    }
    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  List<Widget> _buildDailyGroupedEntries(
    List<FinanceEntry> entries,
    Map<String, FinanceAccountEntry> accountMap,
    FinanceRepository repository,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (entries.isEmpty) return const [];

    final grouped = <DateTime, List<FinanceEntry>>{};
    for (final e in entries) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.occurredAt);
      final dayKey = DateTime(dt.year, dt.month, dt.day);
      grouped.putIfAbsent(dayKey, () => []).add(e);
    }

    final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final widgets = <Widget>[];
    const weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    for (final day in sortedDays) {
      final dayItems = grouped[day]!;
      dayItems.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      int dayExpense = 0;
      int dayIncome = 0;
      for (final it in dayItems) {
        if (it.direction == FinanceDirection.expense && !it.isReimbursable) {
          dayExpense += it.amountMinor;
        } else if (it.direction == FinanceDirection.income) {
          dayIncome += it.amountMinor;
        }
      }

      String dayLabel = '${day.month}月${day.day}日';
      if (day == today) {
        dayLabel += ' 今天';
      } else if (day == yesterday) {
        dayLabel += ' 昨天';
      } else {
        dayLabel += ' ${weekDays[day.weekday - 1]}';
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 12,
                    decoration: BoxDecoration(
                      color: day == today ? colorScheme.primary : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: day == today ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (dayExpense > 0)
                    Text(
                      '支 ¥${(dayExpense / 100).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.deepOrange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (dayExpense > 0 && dayIncome > 0)
                    Text(' · ', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                  if (dayIncome > 0)
                    Text(
                      '收 ¥${(dayIncome / 100).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

      for (final item in dayItems) {
        widgets.add(_buildEntryCard(item, accountMap, repository, colorScheme, theme));
      }
    }

    return widgets;
  }

  Widget _buildBudgetSection({
    required int expenseMinor,
    required int budgetMinor,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    if (budgetMinor <= 0) {
      return const SizedBox.shrink();
    }

    final ratio = expenseMinor / budgetMinor;
    final remainingMinor = budgetMinor - expenseMinor;
    final isOverBudget = remainingMinor < 0;

    final now = DateTime.now();
    final isCurrentMonth = now.year == month.year && now.month == month.month;
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final remainingDays = isCurrentMonth ? (lastDay - now.day + 1).clamp(1, 31) : lastDay;
    final dailyDisposable = remainingMinor > 0 ? (remainingMinor / remainingDays).round() : 0;

    final progressColor = isOverBudget
        ? Colors.red
        : (ratio >= 0.85 ? Colors.orange : colorScheme.primary);

    return Card(
      elevation: 0,
      color: isOverBudget
          ? Colors.red.withValues(alpha: 0.08)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverBudget
              ? Colors.red.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openBudgetDialog(budgetMinor),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(isOverBudget ? Icons.warning_amber_rounded : Icons.account_balance_outlined,
                  size: 16, color: progressColor),
                const SizedBox(width: 6),
                Expanded(child: Text('${month.month}月支出预算: ¥${(budgetMinor / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Icon(Icons.edit_outlined, size: 14, color: colorScheme.outline),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: [
                Text('${(ratio * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: progressColor)),
                Text(isOverBudget
                    ? '已超支 ¥${((-remainingMinor) / 100).toStringAsFixed(2)}'
                    : '剩余 ¥${(remainingMinor / 100).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: progressColor)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  color: progressColor,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4,
                children: [
                  Text(
                    '已支出 ¥${(expenseMinor / 100).toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                  if (isCurrentMonth && !isOverBudget)
                    Text(
                      '剩余 $remainingDays 天 · 建议日均可花 ¥${(dailyDisposable / 100).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.outline),
                    )
                  else if (isOverBudget)
                    const Text(
                      '本月已超支，请注意节约开支',
                      style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBudgetDialog([int? currentBudgetMinor]) async {
    int budget = currentBudgetMinor ?? 0;
    if (currentBudgetMinor == null) {
      final prefs = await SharedPreferences.getInstance();
      budget = FinancePreferences(prefs).getMonthlyBudget(month.year, month.month) ?? 0;
    }
    if (!mounted) return;
    final controller = TextEditingController(
      text: budget > 0 ? (budget / 100).toStringAsFixed(2) : '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设定 ${month.year}年${month.month}月支出预算'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '月预算金额（元）',
            hintText: '如 3000',
            prefixText: '¥ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (budget > 0)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await FinancePreferences(prefs).setMonthlyBudget(month.year, month.month, null);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('清除预算'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              final val = double.tryParse(text);
              if (val != null && val > 0) {
                final prefs = await SharedPreferences.getInstance();
                await FinancePreferences(prefs)
                    .setMonthlyBudget(month.year, month.month, (val * 100).round());
                if (ctx.mounted) Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效金额')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _refresh();
    }
  }

  void _showImportGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: const Text('微信 / 支付宝账单导出指引'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.chat_bubble_outline, color: Color(0xFF07C160)), text: '微信支付'),
                    Tab(icon: Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF1677FF)), text: '支付宝'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: TabBarView(
                    children: [
                      // WeChat Guide
                      ListView(
                        children: const [
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('1', style: TextStyle(fontSize: 12))),
                            title: Text('打开微信「我」➔「服务」➔「钱包」', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('2', style: TextStyle(fontSize: 12))),
                            title: Text('点击右上角「账单」➔ 右上角「常见问题」', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('3', style: TextStyle(fontSize: 12))),
                            title: Text('选择「下载账单」➔「用于个人对账」', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('4', style: TextStyle(fontSize: 12))),
                            title: Text('选择自定义时间范围，输入邮箱接收压缩包', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('5', style: TextStyle(fontSize: 12))),
                            title: Text('解压压缩包（密码为微信公众号提示），在 LifeHub 导入解压出的 .xlsx 或 .csv 文件即可！', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                      // Alipay Guide
                      ListView(
                        children: const [
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('1', style: TextStyle(fontSize: 12))),
                            title: Text('打开支付宝「我的」➔「账单」', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('2', style: TextStyle(fontSize: 12))),
                            title: Text('点击右上角「···」三个点', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('3', style: TextStyle(fontSize: 12))),
                            title: Text('选择「开具交易流水证明」➔「用于个人对账」', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('4', style: TextStyle(fontSize: 12))),
                            title: Text('选择对账时间范围，发送至您的电子邮箱', style: TextStyle(fontSize: 13)),
                          ),
                          ListTile(
                            leading: CircleAvatar(radius: 12, child: Text('5', style: TextStyle(fontSize: 12))),
                            title: Text('解压附件得到 CSV 文件，点击右上角导入按钮选择该文件即可！', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdjustBalanceDialog(
      AccountRepository repo, FinanceAccountEntry account) async {
    final controller = TextEditingController(
        text: (account.balanceMinor / 100).toStringAsFixed(2));

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => KeyboardSafeFormDialog(
        title: Text('校准「${account.name}」余额'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '如查看到实际微信/支付宝/银行卡结余有偏差，可在此直接输入最新真实余额完成对账对齐：',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: '最新实际余额（元） *',
                prefixText: '¥ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              final val = double.tryParse(text);
              if (val == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效金额')),
                );
                return;
              }
              final newMinor = (val * 100).round();
              await repo.adjustBalance(account.id, newMinor - account.balanceMinor);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('完成校准'),
          ),
        ],
      ),
    );

    if (updated == true) _refresh();
  }

  void _showEntryActionSheet(FinanceEntry item, FinanceRepository repository,
      Map<String, FinanceAccountEntry> accountMap) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final title = _cleanTitleText(item.note ?? '');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    title.isNotEmpty ? title : '账单快捷操作',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                      '¥${(item.amountMinor / 100).toStringAsFixed(2)} · ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(item.occurredAt))}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑此账单'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addOrEdit(
                        repository, AccountRepository(ref.read(databaseProvider)),
                        existing: item);
                  },
                ),
                if (item.note?.isNotEmpty == true)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('复制商户/备注文本'),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.note!));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除此账单', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _delete(repository, item);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
