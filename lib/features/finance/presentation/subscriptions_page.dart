import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
      body: FutureBuilder(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('还没有订阅记录'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.autorenew),
                  title: Text(row.name),
                  subtitle: Text(
                    '¥${(row.amountMinor / 100).toStringAsFixed(2)} · 下次 ${DateFormat('yyyy-MM-dd').format(DateKeys.fromLocalDateKey(row.nextRenewalDate))}',
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
      await repository.create(SubscriptionDraft(
        name: name.text,
        amountMinor: (double.parse(amount.text) * 100).round(),
        cycleUnit: cycle,
        nextRenewalDate: date,
      ));
      if (mounted) setState(() => revision++);
    }
    name.dispose();
    amount.dispose();
  }
}
