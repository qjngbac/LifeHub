import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/finance/data/finance_repository.dart';
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
  @override
  Widget build(BuildContext context) {
    final repository = FinanceRepository(ref.read(databaseProvider));
    final end = DateTime(month.year, month.month + 1);
    return Scaffold(
      appBar: AppBar(title: const Text('轻量收支'), actions: [
        IconButton(
          tooltip: '订阅与周期费用',
          icon: const Icon(Icons.autorenew),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(repository),
          icon: const Icon(Icons.add),
          label: const Text('记一笔')),
      body: FutureBuilder<List<Object>>(
        key: ValueKey('$revision-${month.year}-${month.month}'),
        future: Future.wait<Object>([
          repository.monthlySummary(month.year, month.month),
          repository.list(start: month, end: end)
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = snapshot.data![0] as FinanceSummary;
          final entries = snapshot.data![1] as List<FinanceEntry>;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              IconButton(
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: Text('${month.year}年${month.month}月',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1)),
                  icon: const Icon(Icons.chevron_right))
            ]),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _amount('收入', summary.incomeMinor, Colors.green),
                          _amount(
                              '支出', summary.expenseMinor, Colors.deepOrange),
                          _amount('差额', summary.netMinor,
                              Theme.of(context).colorScheme.primary),
                        ]))),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('这里只记录收入与支出事实，不维护账户余额、借贷或转账。')),
            if (entries.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20), child: Text('本月还没有记录'))),
            for (final value in entries)
              Card(
                  child: ListTile(
                leading: CircleAvatar(
                    child: Icon(value.direction == FinanceDirection.income
                        ? Icons.south_west
                        : Icons.north_east)),
                title: Text(value.note ?? _category(value.category)),
                subtitle: Text(
                    '${DateFormat('M月d日').format(DateTime.fromMillisecondsSinceEpoch(value.occurredAt))} · ${_category(value.category)}'),
                trailing: Text(
                    '${value.direction == FinanceDirection.income ? '+' : '-'}¥${(value.amountMinor / 100).toStringAsFixed(2)}'),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(value.note ?? '收支详情')),
                            body: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  EntityRelationsPanel(
                                      entity: EntityReference(
                                          type: 'FINANCE', id: value.id)),
                                  AttachmentPanel(
                                      entityType: 'FINANCE',
                                      entityId: value.id,
                                      sensitive: value.sensitive),
                                ])))),
              )),
            const SizedBox(height: 80),
          ]);
        },
      ),
    );
  }

  Widget _amount(String label, int value, Color color) => Column(children: [
        Text(label),
        Text('¥${(value / 100).toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold))
      ]);

  Future<void> _add(FinanceRepository repository) async {
    var direction = FinanceDirection.expense;
    var category = 'FOOD';
    final amount = TextEditingController();
    final note = TextEditingController();
    final save = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => KeyboardSafeFormDialog(
                  title: const Text('记一笔'),
                  body: Column(mainAxisSize: MainAxisSize.min, children: [
                    SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: FinanceDirection.expense,
                              label: Text('支出')),
                          ButtonSegment(
                              value: FinanceDirection.income, label: Text('收入'))
                        ],
                        selected: {
                          direction
                        },
                        onSelectionChanged: (values) =>
                            setDialogState(() => direction = values.first)),
                    TextField(
                        controller: amount,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: '金额（CNY） *')),
                    DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: '分类'),
                        items: const [
                          'FOOD',
                          'TRANSPORT',
                          'SHOPPING',
                          'HOUSING',
                          'SALARY',
                          'OTHER'
                        ]
                            .map((v) => DropdownMenuItem(
                                value: v, child: Text(_category(v))))
                            .toList(),
                        onChanged: (value) => category = value ?? category),
                    TextField(
                        controller: note,
                        decoration: const InputDecoration(labelText: '说明（可选）')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('保存'))
                  ],
                )));
    if (save == true && amount.text.trim().isNotEmpty) {
      await repository.create(FinanceDraft(
          direction: direction,
          amountMinor: FinanceRepository.parseMinor(amount.text),
          category: category,
          occurredAt: DateTime.now(),
          note: note.text));
      if (mounted) setState(() => revision++);
    }
    amount.dispose();
    note.dispose();
  }
}

String _category(String value) => switch (value) {
      'FOOD' => '餐饮',
      'TRANSPORT' => '交通',
      'SHOPPING' => '购物',
      'HOUSING' => '居住',
      'SALARY' => '收入',
      'OTHER' => '其他',
      _ => value
    };
