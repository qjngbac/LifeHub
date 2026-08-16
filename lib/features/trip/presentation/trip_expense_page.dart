import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/trip/data/trip_expense_repository.dart';
import 'package:lifehub/features/trip/data/trip_repository.dart';

class TripExpensePage extends ConsumerWidget {
  const TripExpensePage({required this.tripId, super.key});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(refreshProvider);
    final repository = TripExpenseRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('旅行账单')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref, repository),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      body: FutureBuilder<List<TripExpenseEntry>>(
        future: repository.list(tripId),
        builder: (context, snapshot) {
          final values = snapshot.data ?? const <TripExpenseEntry>[];
          return FutureBuilder<
              (Map<String, int>, Map<String, Map<String, int>>)>(
            future: _loadSummary(repository),
            builder: (context, summary) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('合计',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if ((summary.data?.$1 ?? {}).isEmpty)
                          const Text('暂无花费')
                        else
                          for (final entry in summary.data!.$1.entries)
                            Text(
                              '${entry.key} ${(entry.value / 100).toStringAsFixed(2)}',
                            ),
                        const SizedBox(height: 4),
                        const Text('不同币种分开统计，不做隐式汇率换算。'),
                        if ((summary.data?.$2 ?? {}).isNotEmpty) ...[
                          const Divider(height: 24),
                          Text('按付款人',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          for (final currency in summary.data!.$2.entries)
                            for (final payer in currency.value.entries)
                              Text(
                                '${payer.key}：${currency.key} ${(payer.value / 100).toStringAsFixed(2)}',
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (values.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('还没有记录花费')),
                  ),
                ...values.map(
                  (expense) => Card(
                    child: ListTile(
                      title: Text(expense.title),
                      subtitle: Text(
                        '${_category(expense.category)} · ${_date(expense.expenseDate)}'
                        '${expense.payer == null ? '' : ' · ${expense.payer}'}',
                      ),
                      trailing: Text(
                        '${expense.currency} ${(expense.amountCents / 100).toStringAsFixed(2)}',
                      ),
                      onTap: () => _expenseDetail(context, expense),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<(Map<String, int>, Map<String, Map<String, int>>)> _loadSummary(
    TripExpenseRepository repository,
  ) async =>
      (
        await repository.totalsByCurrency(tripId),
        await repository.payerTotals(tripId),
      );

  void _expenseDetail(BuildContext context, TripExpenseEntry expense) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(expense.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${expense.currency} ${(expense.amountCents / 100).toStringAsFixed(2)}',
              ),
              const SizedBox(height: 4),
              Text(
                  '${_category(expense.category)} · ${_date(expense.expenseDate)}'),
              AttachmentPanel(
                entityType: 'TRIP_EXPENSE',
                entityId: expense.id,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    TripExpenseRepository repository,
  ) async {
    final trip = await TripRepository(ref.read(databaseProvider)).get(tripId);
    if (!context.mounted) return;
    final title = TextEditingController();
    final amount = TextEditingController();
    final payer = TextEditingController();
    var date = DateKeys.fromLocalDateKey(trip.startDate);
    var category = TripExpenseCategory.other;
    var currency = 'CNY';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('记录花费'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '项目'),
              ),
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '金额'),
              ),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: '币种'),
                items: const {
                  'CNY': '人民币（CNY）',
                  'USD': '美元（USD）',
                  'EUR': '欧元（EUR）',
                  'JPY': '日元（JPY）',
                }
                    .entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (value) => setLocal(() => currency = value!),
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: TripExpenseCategory.values
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text(_category(value))))
                    .toList(),
                onChanged: (value) => setLocal(() => category = value!),
              ),
              TextField(
                controller: payer,
                decoration: const InputDecoration(labelText: '付款人（可选）'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('日期'),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(date)),
                onTap: () async {
                  final value = await showDatePicker(
                    context: context,
                    firstDate: DateKeys.fromLocalDateKey(trip.startDate),
                    lastDate: DateKeys.fromLocalDateKey(trip.endDate),
                    initialDate: date,
                  );
                  if (value != null) setLocal(() => date = value);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final parsed = double.tryParse(amount.text);
    if (accepted != true ||
        title.text.trim().isEmpty ||
        parsed == null ||
        parsed <= 0) {
      return;
    }
    await repository.create(TripExpenseDraft(
      tripId: tripId,
      title: title.text,
      amountCents: (parsed * 100).round(),
      currency: currency,
      expenseDate: date,
      category: category,
      payer: payer.text,
    ));
    ref.read(refreshProvider.notifier).state++;
  }
}

String _date(int key) =>
    DateFormat('MM-dd').format(DateKeys.fromLocalDateKey(key));

String _category(String value) => switch (value) {
      TripExpenseCategory.transport => '交通',
      TripExpenseCategory.lodging => '住宿',
      TripExpenseCategory.food => '餐饮',
      TripExpenseCategory.ticket => '门票',
      TripExpenseCategory.shopping => '购物',
      _ => '其他',
    };
