import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/application/bill_csv_parser.dart';
import 'package:lifehub/features/finance/application/bill_import_service.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/domain/finance_models.dart';

class BillImportPreviewPage extends ConsumerStatefulWidget {
  const BillImportPreviewPage({
    required this.rawItems,
    super.key,
  });

  final List<ParsedBillItem> rawItems;

  @override
  ConsumerState<BillImportPreviewPage> createState() =>
      _BillImportPreviewPageState();
}

class _BillImportPreviewPageState
    extends ConsumerState<BillImportPreviewPage> {
  late List<ParsedBillItem> _items;
  List<FinanceAccountEntry> _accounts = [];
  bool _isLoading = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _items = widget.rawItems;
    _initialize();
  }

  Future<void> _initialize() async {
    final db = ref.read(databaseProvider);
    final service = BillImportService(db);
    final accountRepo = AccountRepository(db);

    await service.checkDuplicates(_items);
    await service.autoAssignAccounts(_items);
    final accounts = await accountRepo.listAccounts();

    if (mounted) {
      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    }
  }

  void _selectAll(bool select) {
    setState(() {
      for (final item in _items) {
        if (!item.isDuplicate) {
          item.selected = select;
        }
      }
    });
  }

  void _batchSetAccount(String accountId) {
    setState(() {
      for (final item in _items) {
        if (item.selected) {
          item.assignedAccountId = accountId;
        }
      }
    });
  }

  Future<void> _executeImport() async {
    final toImport = _items.where((e) => e.selected && !e.isDuplicate).toList();
    if (toImport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少勾选一笔待导入流水')),
      );
      return;
    }

    setState(() => _isImporting = true);

    try {
      final db = ref.read(databaseProvider);
      final service = BillImportService(db);
      final result = await service.importBatch(_items);

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('账单批量导入完成'),
            content: Text(
              '成功导入 ${result.importedCount} 笔流水！\n'
              '总支出：¥${(result.totalExpenseMinor / 100).toStringAsFixed(2)}\n'
              '总收入/提现：¥${(result.totalIncomeMinor / 100).toStringAsFixed(2)}\n'
              '已自动防重跳过 ${result.skippedCount} 笔流水。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好的'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    int selectedCount = 0;
    int selectedExpenseMinor = 0;
    int selectedIncomeMinor = 0;
    int duplicateCount = 0;

    for (final it in _items) {
      if (it.isDuplicate) duplicateCount++;
      if (it.selected && !it.isDuplicate) {
        selectedCount++;
        if (it.direction == FinanceDirection.income) {
          selectedIncomeMinor += it.amountMinor;
        } else if (it.direction == FinanceDirection.expense) {
          selectedExpenseMinor += it.amountMinor;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单批量导入预览'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'select_all') _selectAll(true);
              if (val == 'unselect_all') _selectAll(false);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'select_all', child: Text('全选有效条目')),
              PopupMenuItem(value: 'unselect_all', child: Text('全部取消选择')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已勾选 $selectedCount / ${_items.length} 笔',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '支出: ¥${(selectedExpenseMinor / 100).toStringAsFixed(2)} | 收入: ¥${(selectedIncomeMinor / 100).toStringAsFixed(2)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isImporting ? null : _executeImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_done),
                label: const Text('确认批量入账'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Overview Card
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '识别到 ${_items.length} 笔流水 (已自动防重排查 $duplicateCount 笔)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '系统已根据商户名称智能推断分类与对应扣款账户。可直接点击列表进行调整，未勾选或已重复项将不会导入。',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                  if (_accounts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('批量指定账户: ', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text('统一设置已选条目的账户',
                                style: TextStyle(fontSize: 12)),
                            items: _accounts
                                .map((a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text(a.name,
                                          style: const TextStyle(fontSize: 12)),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) _batchSetAccount(val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Items List
          for (int i = 0; i < _items.length; i++)
            _buildBillItemCard(_items[i], i),
        ],
      ),
    );
  }

  Widget _buildBillItemCard(ParsedBillItem item, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isIncome = item.direction == FinanceDirection.income;
    final isTransfer = item.direction == FinanceDirection.transfer;
    final dateStr = DateFormat('MM-dd HH:mm').format(item.transactionTime);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: item.isDuplicate
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: item.selected
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: item.selected && !item.isDuplicate,
              onChanged: item.isDuplicate
                  ? null
                  : (val) => setState(() => item.selected = val ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.counterparty.isNotEmpty
                              ? item.counterparty
                              : item.description,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: item.isDuplicate ? colorScheme.outline : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${isIncome ? '+' : (isTransfer ? '' : '-')}¥${(item.amountMinor / 100).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome
                              ? Colors.green
                              : (isTransfer
                                  ? colorScheme.primary
                                  : (item.isDuplicate
                                      ? colorScheme.outline
                                      : colorScheme.error)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colorScheme.outline),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.sourcePaymentMethod,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colorScheme.outline),
                      ),
                      if (item.isDuplicate) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '已存在/重复',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Direction Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isIncome
                              ? Colors.green.withValues(alpha: 0.12)
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isIncome ? '收入' : (isTransfer ? '转账/提现' : '支出'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isIncome ? Colors.green : null,
                          ),
                        ),
                      ),
                      // Category Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${FinanceCategoryCatalog.label(item.category)}${item.subCategory != null ? ' · ${item.subCategory}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.secondary,
                          ),
                        ),
                      ),
                      // Account Selector Dropdown
                      if (_accounts.isNotEmpty && !item.isDuplicate)
                        DropdownButton<String>(
                          value: item.assignedAccountId,
                          isDense: true,
                          style: theme.textTheme.labelSmall,
                          underline: const SizedBox(),
                          items: _accounts
                              .map((a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text(a.name,
                                        style: const TextStyle(fontSize: 11)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => item.assignedAccountId = val);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
