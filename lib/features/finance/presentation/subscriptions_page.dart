import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/finance/data/subscription_repository.dart';
import 'package:lifehub/features/finance/domain/subscription_rules.dart';
import 'package:lifehub/features/finance/presentation/subscription_detail_page.dart';

class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  var revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = SubscriptionRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('订阅与周期费用')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('订阅'),
      ),
      body: FutureBuilder<List<SubscriptionEntry>>(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          if (rows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.subscriptions_outlined,
                      size: 56,
                      color: colorScheme.outline.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text('还没有订阅记录'),
                  const SizedBox(height: 4),
                  Text(
                    '点击下方按钮添加如会员、宽带、租金等周期支出',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          int totalAnnualMinor = 0;
          for (final row in rows) {
            final unit = SubscriptionCycleUnitValue.fromDb(row.cycleUnit);
            switch (unit) {
              case SubscriptionCycleUnit.week:
                totalAnnualMinor += row.amountMinor * 52;
                break;
              case SubscriptionCycleUnit.month:
                totalAnnualMinor += row.amountMinor * 12;
                break;
              case SubscriptionCycleUnit.year:
                totalAnnualMinor += row.amountMinor;
                break;
              case SubscriptionCycleUnit.fixedDays:
                final days = row.fixedDays ?? 30;
                totalAnnualMinor += (row.amountMinor * 365 / days).round();
                break;
            }
          }
          final monthlyAvgMinor = (totalAnnualMinor / 12).round();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            children: [
              // Annual Overview Card
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
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
                              Icon(Icons.all_inclusive_rounded,
                                  size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '周期开销全貌',
                                style:
                                    theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${rows.length} 项有效订阅',
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('年化固定开销',
                                  style: theme.textTheme.labelSmall),
                              const SizedBox(height: 4),
                              Text(
                                '¥${(totalAnnualMinor / 100).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                          Container(
                              height: 36,
                              width: 1,
                              color: colorScheme.outlineVariant),
                          Column(
                            children: [
                              Text('折合月均负担',
                                  style: theme.textTheme.labelSmall),
                              const SizedBox(height: 4),
                              Text(
                                '¥${(monthlyAvgMinor / 100).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Subscription Item Cards
              for (final row in rows) ...[
                Builder(
                  builder: (context) {
                    final unit =
                        SubscriptionCycleUnitValue.fromDb(row.cycleUnit);
                    final cycleLabel = switch (unit) {
                      SubscriptionCycleUnit.week => '周',
                      SubscriptionCycleUnit.month => '月',
                      SubscriptionCycleUnit.year => '年',
                      SubscriptionCycleUnit.fixedDays =>
                        '${row.fixedDays ?? 30}天',
                    };
                    final int annualAmount = switch (unit) {
                      SubscriptionCycleUnit.week => row.amountMinor * 52,
                      SubscriptionCycleUnit.month => row.amountMinor * 12,
                      SubscriptionCycleUnit.year => row.amountMinor,
                      SubscriptionCycleUnit.fixedDays =>
                        (row.amountMinor * 365 / (row.fixedDays ?? 30)).round(),
                    };

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              colorScheme.primaryContainer,
                          child: Icon(Icons.autorenew,
                              color: colorScheme.primary),
                        ),
                        title: Text(row.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              '¥${(row.amountMinor / 100).toStringAsFixed(2)} / $cycleLabel (年化约 ¥${(annualAmount / 100).toStringAsFixed(0)})',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '下次续费: ${DateFormat('yyyy-MM-dd').format(DateKeys.fromLocalDateKey(row.nextRenewalDate))}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: colorScheme.outline),
                            ),
                          ],
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            await repository.confirmCharge(row.id,
                                cycleDate: row.nextRenewalDate);
                            if (mounted) setState(() => revision++);
                          },
                          child: const Text('确认扣费'),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SubscriptionDetailPage(
                              subscription: row,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(SubscriptionRepository repository) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    var cycle = SubscriptionCycleUnit.month;
    var date = DateTime.now();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加订阅'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名称')),
              TextField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '金额（CNY）')),
              DropdownButtonFormField<SubscriptionCycleUnit>(
                initialValue: cycle,
                decoration: const InputDecoration(labelText: '周期'),
                items: const [
                  DropdownMenuItem(
                      value: SubscriptionCycleUnit.week, child: Text('每周')),
                  DropdownMenuItem(
                      value: SubscriptionCycleUnit.month, child: Text('每月')),
                  DropdownMenuItem(
                      value: SubscriptionCycleUnit.year, child: Text('每年')),
                ],
                onChanged: (value) => cycle = value ?? cycle,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('下次续费'),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(date)),
                onTap: () async {
                  final next = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: date,
                      barrierDismissible: false);
                  if (next != null) setDialogState(() => date = next);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      final parsedAmount = double.tryParse(amount.text.trim());
      if (parsedAmount == null || parsedAmount < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入有效的金额')),
          );
        }
      } else {
        await repository.create(SubscriptionDraft(
          name: name.text.trim(),
          amountMinor: (parsedAmount * 100).round(),
          cycleUnit: cycle,
          nextRenewalDate: date,
        ));
        if (mounted) setState(() => revision++);
      }
    }
    name.dispose();
    amount.dispose();
  }
}
