import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/finance/data/account_repository.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';

class ReimbursementListPage extends ConsumerStatefulWidget {
  const ReimbursementListPage({super.key});

  @override
  ConsumerState<ReimbursementListPage> createState() =>
      _ReimbursementListPageState();
}

class _ReimbursementListPageState extends ConsumerState<ReimbursementListPage> {
  int _revision = 0;
  String _filter = 'UNPAID'; // UNPAID, ALL, REIMBURSED

  void _refresh() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final database = ref.watch(databaseProvider);
    final financeRepo = FinanceRepository(database);
    final accountRepo = AccountRepository(database);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待报销与垫付清单'),
      ),
      body: FutureBuilder<List<Object>>(
        key: ValueKey('reimburse_$_revision'),
        future: Future.wait<Object>([
          financeRepo.list(
            isReimbursable: true,
            reimburseStatus: _filter == 'ALL' ? null : _filter,
          ),
          accountRepo.listAccounts(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data![0] as List<FinanceEntry>;
          final accounts = snapshot.data![1] as List<FinanceAccountEntry>;
          final accountMap = {for (final a in accounts) a.id: a};

          int pendingTotalMinor = 0;
          for (final e in entries) {
            if (e.reimburseStatus == 'UNPAID') {
              pendingTotalMinor += e.amountMinor;
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              Card(
                elevation: 0,
                color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                      color: colorScheme.tertiary.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            colorScheme.tertiary.withValues(alpha: 0.2),
                        child: Icon(Icons.receipt_long_outlined,
                            color: colorScheme.tertiary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '待收回垫付 / 报销总额',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '¥${(pendingTotalMinor / 100).toStringAsFixed(2)}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.tertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '垫付款项已从生活消费中自动剔除，不虚增净支出',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'UNPAID', label: Text('未报销/未收')),
                  ButtonSegment(value: 'ALL', label: Text('全部垫付')),
                  ButtonSegment(value: 'REIMBURSED', label: Text('已收回')),
                ],
                selected: {_filter},
                onSelectionChanged: (val) =>
                    setState(() => _filter = val.first),
              ),
              const SizedBox(height: 14),

              if (entries.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 48, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('暂无符合条件的垫付/报销条目',
                            style: TextStyle(color: colorScheme.outline)),
                      ],
                    ),
                  ),
                )
              else
                for (final item in entries)
                  _ReimbursementCard(
                    entry: item,
                    accountName: item.accountId != null
                        ? accountMap[item.accountId]?.name ?? '未知账户'
                        : '默认账户',
                    onResolve: () => _resolveReimbursement(
                        financeRepo, accounts, item),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _resolveReimbursement(FinanceRepository repo,
      List<FinanceAccountEntry> accounts, FinanceEntry item) async {
    String? targetAccId = item.accountId ?? (accounts.isNotEmpty ? accounts.first.id : null);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('平账：确认收到报销款？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('条目：${item.note?.isNotEmpty == true ? item.note! : item.category}'),
              Text('金额：¥${(item.amountMinor / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 14),
              const Text('这笔钱报销回款到了哪个账户？', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: targetAccId,
                decoration: const InputDecoration(
                  labelText: '回款入账账户',
                  border: OutlineInputBorder(),
                ),
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        ))
                    .toList(),
                onChanged: (val) => setDialogState(() => targetAccId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认平账入账'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await repo.markReimbursed(item.id, targetAccountId: targetAccId);
      _refresh();
    }
  }
}

class _ReimbursementCard extends StatelessWidget {
  const _ReimbursementCard({
    required this.entry,
    required this.accountName,
    required this.onResolve,
  });

  final FinanceEntry entry;
  final String accountName;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUnpaid = entry.reimburseStatus == 'UNPAID';
    final dateStr = DateFormat('yyyy年M月d日')
        .format(DateTime.fromMillisecondsSinceEpoch(entry.occurredAt));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUnpaid
              ? colorScheme.tertiary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.note?.isNotEmpty == true ? entry.note! : entry.category,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  '¥${(entry.amountMinor / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isUnpaid ? colorScheme.tertiary : colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(dateStr,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.outline)),
                const SizedBox(width: 8),
                Text('垫付账户: $accountName',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.outline)),
                if (entry.subCategory?.isNotEmpty == true) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(entry.subCategory!,
                        style: theme.textTheme.labelSmall),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isUnpaid
                        ? colorScheme.errorContainer.withValues(alpha: 0.5)
                        : Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isUnpaid ? '待报销收回' : '已核销入账',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isUnpaid ? colorScheme.error : Colors.green,
                    ),
                  ),
                ),
                if (isUnpaid)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('收到回款平账'),
                    onPressed: onResolve,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
