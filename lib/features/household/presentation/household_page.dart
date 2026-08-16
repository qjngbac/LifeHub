import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/household/data/household_repository.dart';
import 'package:lifehub/features/household/presentation/maintenance_page.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class HouseholdPage extends ConsumerStatefulWidget {
  const HouseholdPage({super.key});
  @override
  ConsumerState<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends ConsumerState<HouseholdPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = HouseholdRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('家庭物品与保修'), actions: [
        IconButton(
          tooltip: '周期维护',
          icon: const Icon(Icons.home_repair_service_outlined),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MaintenancePage())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('物品'),
      ),
      body: FutureBuilder<List<HouseholdItemEntry>>(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = snapshot.data!;
          if (values.isEmpty) {
            return const Center(child: Text('记录家电、数码产品和保修截止时间'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: values.length,
            itemBuilder: (context, index) {
              final value = values[index];
              final state = repository.warrantyState(value, DateTime.now());
              final consumable = value.itemKind == 'CONSUMABLE'
                  ? repository.consumableState(value, DateTime.now())
                  : null;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(value.name),
                  subtitle: Text(consumable == null
                      ? _warranty(value, state)
                      : '${value.quantity}${value.unit ?? ''}${consumable.expired ? ' · 已过期' : consumable.expiringSoon ? ' · 即将到期' : ''}${consumable.lowStock ? ' · 需要补货' : ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _HouseholdDetail(itemId: value.id)),
                    );
                    if (mounted) setState(() => revision++);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(HouseholdRepository repository) async {
    final draft = await _showHouseholdForm(context);
    if (draft != null) {
      await repository.create(draft);
      if (mounted) setState(() => revision++);
    }
  }
}

Future<HouseholdDraft?> _showHouseholdForm(
  BuildContext context, {
  HouseholdItemEntry? current,
}) async {
  final name = TextEditingController(text: current?.name);
  final brand = TextEditingController(text: current?.brandModel);
  final amount = TextEditingController(
      text: current?.purchaseAmountMinor == null
          ? ''
          : (current!.purchaseAmountMinor! / 100).toStringAsFixed(2));
  final quantity = TextEditingController(text: '${current?.quantity ?? 1}');
  final unit = TextEditingController(text: current?.unit);
  final notes = TextEditingController(text: current?.notes);
  var kind = current?.itemKind == 'CONSUMABLE'
      ? HouseholdItemKind.consumable
      : HouseholdItemKind.durable;
  DateTime? purchase = current?.purchaseDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.purchaseDate!);
  DateTime? warranty = current?.warrantyEndDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.warrantyEndDate!);
  DateTime? expiry = current?.expiryDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.expiryDate!);
  final draft = await showDialog<HouseholdDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
              title: Text(current == null ? '添加家庭物品' : '编辑家庭物品'),
              body: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '名称 *')),
                TextField(
                    controller: brand,
                    decoration: const InputDecoration(labelText: '品牌 / 型号')),
                TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '购买金额（元，可选）')),
                _DateTile(
                    label: '购买日期',
                    value: purchase,
                    onChanged: (v) => setDialogState(() => purchase = v)),
                _DateTile(
                    label: '保修截止',
                    value: warranty,
                    onChanged: (v) => setDialogState(() => warranty = v)),
                DropdownButtonFormField<HouseholdItemKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '物品类型'),
                  items: const [
                    DropdownMenuItem(
                        value: HouseholdItemKind.durable, child: Text('耐用品')),
                    DropdownMenuItem(
                        value: HouseholdItemKind.consumable,
                        child: Text('消耗品')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? kind),
                ),
                TextField(
                    controller: quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '数量')),
                TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: '单位（可选）')),
                _DateTile(
                    label: '保质期',
                    value: expiry,
                    onChanged: (v) => setDialogState(() => expiry = v)),
                TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '备注（可选）')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () {
                      final title = name.text.trim();
                      if (title.isEmpty) return;
                      final parsedAmount = double.tryParse(amount.text.trim());
                      Navigator.pop(
                          context,
                          HouseholdDraft(
                            name: title,
                            brandModel: brand.text,
                            purchaseDate: purchase,
                            purchaseAmountMinor: parsedAmount == null
                                ? null
                                : (parsedAmount * 100).round(),
                            warrantyEndDate: warranty,
                            itemKind: kind,
                            quantity: double.tryParse(quantity.text) ?? 1,
                            unit: unit.text,
                            expiryDate: expiry,
                            notes: notes.text,
                            sensitive: current?.sensitive ?? false,
                          ));
                    },
                    child: const Text('保存')),
              ],
            )),
  );
  name.dispose();
  brand.dispose();
  amount.dispose();
  quantity.dispose();
  unit.dispose();
  notes.dispose();
  return draft;
}

class _DateTile extends StatelessWidget {
  const _DateTile(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(
            value == null ? '未设置' : DateFormat('yyyy-MM-dd').format(value!)),
        trailing: const Icon(Icons.event_outlined),
        onTap: () async {
          final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              barrierDismissible: false);
          if (picked != null) onChanged(picked);
        },
      );
}

class _HouseholdDetail extends ConsumerStatefulWidget {
  const _HouseholdDetail({required this.itemId});
  final String itemId;
  @override
  ConsumerState<_HouseholdDetail> createState() => _HouseholdDetailState();
}

class _HouseholdDetailState extends ConsumerState<_HouseholdDetail> {
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = HouseholdRepository(ref.read(databaseProvider));
    return FutureBuilder<HouseholdItemEntry>(
        key: ValueKey(revision),
        future: repository.get(widget.itemId),
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return Scaffold(
              appBar: AppBar(title: Text(item.name), actions: [
                PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final draft =
                            await _showHouseholdForm(context, current: item);
                        if (draft != null) {
                          await repository.update(item.id, draft);
                          if (mounted) setState(() => revision++);
                        }
                      } else {
                        final yes = await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => AlertDialog(
                                        title: Text('删除“${item.name}”？'),
                                        content:
                                            const Text('删除后将不再显示该物品的保修信息。'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('取消')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('删除'))
                                        ])) ??
                            false;
                        if (yes) {
                          await repository.delete(item.id);
                          if (context.mounted) Navigator.pop(context);
                        }
                      }
                    },
                    itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('编辑'))),
                          PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                  leading: Icon(Icons.delete_outline,
                                      color:
                                          Theme.of(context).colorScheme.error),
                                  title: Text('删除',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))))
                        ])
              ]),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.brandModel ?? '未填写品牌型号',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              if (item.purchaseAmountMinor != null)
                                Text(
                                    '购买金额：¥${(item.purchaseAmountMinor! / 100).toStringAsFixed(2)}'),
                              if (item.warrantyEndDate != null)
                                Text(
                                    '保修至：${DateFormat('yyyy-MM-dd').format(DateKeys.fromLocalDateKey(item.warrantyEndDate!))}'),
                              if (item.notes != null) Text(item.notes!),
                              if (item.itemKind == 'CONSUMABLE') ...[
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () async {
                                    await HouseholdRepository(
                                      ref.read(databaseProvider),
                                    ).addToShoppingList(item.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('已加入购物清单')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.add_shopping_cart),
                                  label: const Text('加入购物清单'),
                                ),
                              ],
                            ]))),
                EntityRelationsPanel(
                    entity: EntityReference(type: 'HOUSEHOLD', id: item.id)),
                AttachmentPanel(
                    entityType: 'HOUSEHOLD',
                    entityId: item.id,
                    sensitive: item.sensitive),
              ]));
        });
  }
}

String _warranty(HouseholdItemEntry item, WarrantyState state) =>
    switch (state) {
      WarrantyState.none => item.brandModel ?? '未设置保修时间',
      WarrantyState.active => '保修中 · ${item.brandModel ?? ''}',
      WarrantyState.expiringSoon => '保修即将到期 · ${item.brandModel ?? ''}',
      WarrantyState.expired => '保修已到期 · ${item.brandModel ?? ''}',
    };
