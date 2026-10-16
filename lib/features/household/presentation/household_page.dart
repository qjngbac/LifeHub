import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/household/data/household_repository.dart';
import 'package:lifehub/features/household/domain/consumable_rules.dart';
import 'package:lifehub/features/household/presentation/maintenance_page.dart';
import 'package:lifehub/features/relations/domain/related_entity.dart';
import 'package:lifehub/features/relations/presentation/entity_relations_panel.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

/// 表单统一的输入框样式。
///
/// 全局主题里的 `inputDecorationTheme` 是"白色 78% 填充 + 无边框"，
/// 而对话框底色是近白（`0xFFFFFBFF`）——两者叠在一起输入区几乎隐形，
/// 用户看不出哪儿能点。这里显式换成可辨识的浅灰底 + 淡描边。
InputDecoration _fieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  String? suffix,
  String? errorText,
}) {
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  final idle = scheme.outlineVariant.withValues(alpha: 0.75);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    errorText: errorText,
    isDense: true,
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(idle, 1),
    enabledBorder: border(idle, 1),
    focusedBorder: border(scheme.primary, 1.6),
  );
}

class HouseholdPage extends ConsumerStatefulWidget {
  const HouseholdPage({super.key});
  @override
  ConsumerState<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends ConsumerState<HouseholdPage> {
  int revision = 0;
  String filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final repository = HouseholdRepository(ref.read(databaseProvider));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭物品与保修'),
        actions: [
          IconButton(
            tooltip: '周期维护',
            icon: const Icon(Icons.home_repair_service_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MaintenancePage()),
            ),
          ),
        ],
      ),
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
          // 预计算每条的状态，避免筛选与列表各算一遍
          final rows = [
            for (final item in snapshot.data!)
              _ItemRow(
                item: item,
                now: now,
                warranty: repository.warrantyState(item, now),
                consumable: item.itemKind == 'CONSUMABLE'
                    ? repository.consumableState(item, now)
                    : null,
              ),
          ];
          final counts = <String, int>{
            'ALL': rows.length,
            'WARRANTY': rows.where((row) => row.inWarranty).length,
            'EXPIRING': rows.where((row) => row.needsAttention).length,
            'LOW_STOCK': rows.where((row) => row.lowStock).length,
          };
          final values = rows.where((row) => row.matches(filter)).toList();

          return Column(
            children: [
              _buildFilters(counts),
              Expanded(child: _buildList(values, rows.isEmpty)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters(Map<String, int> counts) {
    const entries = [
      ('ALL', '全部'),
      ('WARRANTY', '保修中'),
      ('EXPIRING', '临期 / 已过期'),
      ('LOW_STOCK', '需补货'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in entries) ...[
              if (value != 'ALL') const SizedBox(width: 8),
              FilterChip(
                label: Text('$label ${counts[value] ?? 0}'),
                selected: filter == value,
                onSelected: (_) => setState(() => filter = value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<_ItemRow> values, bool nothingAtAll) {
    if (nothingAtAll) {
      return _EmptyState(
        icon: Icons.inventory_2_outlined,
        title: '还没有记录任何物品',
        message: '家电数码记保修，日用消耗品记库存与保质期，\n到期前会自动提醒。',
        actionLabel: '添加第一个物品',
        onAction: () => _add(HouseholdRepository(ref.read(databaseProvider))),
      );
    }
    if (values.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '当前筛选下没有物品',
        message: '换个筛选条件看看，或者补充一条新记录。',
        actionLabel: '查看全部',
        onAction: () => setState(() => filter = 'ALL'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemCount: values.length,
      itemBuilder: (context, index) => _buildTile(values[index]),
    );
  }

  Widget _buildTile(_ItemRow row) {
    final value = row.item;
    final isConsumable = row.consumable != null;
    final badge = row.badge;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _HouseholdDetail(itemId: value.id),
            ),
          );
          if (mounted) setState(() => revision++);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(
                isConsumable
                    ? Icons.shopping_basket_outlined
                    : Icons.devices_other_outlined,
                color: switch (badge?.tone) {
                  2 => theme.colorScheme.error,
                  1 => Colors.orange.shade700,
                  _ => theme.colorScheme.primary,
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            value.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          _StatusBadge(text: badge.text, tone: badge.tone),
                        ],
                      ],
                    ),
                    if (row.specsSubtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        row.specsSubtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (row.dateSubtitle != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isConsumable
                                ? Icons.event_available_outlined
                                : Icons.verified_user_outlined,
                            size: 13,
                            color: switch (badge?.tone) {
                              2 => theme.colorScheme.error,
                              1 => Colors.orange.shade700,
                              _ => theme.colorScheme.primary,
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            row.dateSubtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: switch (badge?.tone) {
                                2 => theme.colorScheme.error,
                                1 => Colors.orange.shade800,
                                _ => theme.colorScheme.onSurfaceVariant,
                              },
                              fontWeight:
                                  badge?.tone != null && badge!.tone > 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ] else if (row.specsSubtitle == null) ...[
                      const SizedBox(height: 3),
                      Text(
                        isConsumable ? '未设置单位与阈值' : '未填写品牌与型号',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isConsumable)
                _QuantityStepper(
                  quantity: value.quantity,
                  onChanged: (delta) async {
                    final repository =
                        HouseholdRepository(ref.read(databaseProvider));
                    await repository.adjustQuantity(value.id, delta);
                    if (mounted) setState(() => revision++);
                  },
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(HouseholdRepository repository) async {
    final draft = await _showHouseholdForm(context);
    if (draft == null) return;
    await repository.create(draft);
    if (!mounted) return;
    setState(() => revision++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已添加「${draft.name}」')));
  }
}

/// 列表一行的派生状态：一次算好，筛选 / 徽章 / 副标题都复用它。
class _ItemRow {
  const _ItemRow({
    required this.item,
    required this.now,
    required this.warranty,
    required this.consumable,
  });

  final HouseholdItemEntry item;
  final DateTime now;
  final WarrantyState warranty;
  final ConsumableState? consumable;

  bool get lowStock => consumable?.lowStock ?? false;
  bool get expiring => consumable?.expiringSoon ?? false;
  bool get expired => consumable?.expired ?? false;

  bool get inWarranty =>
      warranty == WarrantyState.active || warranty == WarrantyState.expiringSoon;

  bool get needsAttention =>
      warranty == WarrantyState.expiringSoon ||
      warranty == WarrantyState.expired ||
      expiring ||
      expired;

  bool matches(String filter) => switch (filter) {
        'WARRANTY' => inWarranty,
        'EXPIRING' => needsAttention,
        'LOW_STOCK' => lowStock,
        _ => true,
      };

  /// 状态徽章：2 = 红（已失效）、1 = 橙（要处理）、0 = 普通提醒。
  ({String text, int tone})? get badge {
    if (expired) return (text: '已过期', tone: 2);
    if (warranty == WarrantyState.expired) return (text: '保修已到期', tone: 2);
    if (lowStock) return (text: '需补货', tone: 1);
    if (expiring) return (text: '临期', tone: 1);
    if (warranty == WarrantyState.expiringSoon) {
      final end = item.warrantyEndDate;
      if (end != null) {
        final days = DateKeys.fromLocalDateKey(end)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        return (text: days <= 0 ? '今天到期' : '剩 $days 天', tone: 1);
      }
      return (text: '即将到期', tone: 1);
    }
    if (warranty == WarrantyState.active) return (text: '保修中', tone: 0);
    return null;
  }

  /// 规格与品牌/金额等基础信息（不再将保修/保质截止日机械挤在同一行末尾）
  String? get specsSubtitle {
    if (consumable != null) {
      final parts = <String>[];
      if ((item.unit ?? '').trim().isNotEmpty) parts.add('单位 ${item.unit}');
      final minimum = item.minimumQuantity;
      if (minimum != null) {
        parts.add('低于 ${_number(minimum)} 提醒');
      }
      return parts.isEmpty ? null : parts.join(' · ');
    }
    final parts = <String>[];
    final brand = (item.brandModel ?? '').trim();
    if (brand.isNotEmpty) parts.add(brand);
    if (item.purchaseAmountMinor != null) {
      parts.add('¥${(item.purchaseAmountMinor! / 100).toStringAsFixed(2)}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 保修或保质截止日期（独立排布，彻底杜绝被长品牌截断或挤出省略号）
  String? get dateSubtitle {
    if (consumable != null) {
      if (item.expiryDate != null) {
        return '保质至 ${_shortDate(item.expiryDate!)}';
      }
      return null;
    }
    if (item.warrantyEndDate != null) {
      return '保修至 ${_shortDate(item.warrantyEndDate!)}';
    }
    return null;
  }

  /// 兜底副标题文案（兼顾旧接口与测试断言）
  String get subtitle {
    final s = specsSubtitle;
    final d = dateSubtitle;
    if (s != null && d != null) return '$s · $d';
    if (s != null) return s;
    if (d != null) return d;
    return consumable != null ? '未设置单位与阈值' : '未填写品牌与型号';
  }
}

String _shortDate(int key) {
  final date = DateKeys.fromLocalDateKey(key);
  return DateFormat('yyyy-MM-dd').format(date);
}

String _number(double value) =>
    value.toInt() == value ? '${value.toInt()}' : '$value';

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.tone});
  final String text;
  final int tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (Color bg, Color fg) = switch (tone) {
      2 => (scheme.errorContainer, scheme.onErrorContainer),
      1 => (
          isDark ? const Color(0x4D8A5300) : const Color(0xFFFFE7C2),
          isDark ? const Color(0xFFFFD08A) : const Color(0xFF7A4B00),
        ),
      _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});
  final double quantity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 22),
          visualDensity: VisualDensity.compact,
          tooltip: '减少 1',
          onPressed: () => onChanged(-1),
        ),
        SizedBox(
          width: 26,
          child: Text(
            _number(quantity),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 22),
          visualDensity: VisualDensity.compact,
          tooltip: '增加 1',
          onPressed: () => onChanged(1),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

Future<HouseholdDraft?> _showHouseholdForm(
  BuildContext context, {
  HouseholdItemEntry? current,
}) {
  return showDialog<HouseholdDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _HouseholdFormDialog(current: current),
  );
}

class _HouseholdFormDialog extends StatefulWidget {
  const _HouseholdFormDialog({this.current});
  final HouseholdItemEntry? current;

  @override
  State<_HouseholdFormDialog> createState() => _HouseholdFormDialogState();
}

class _HouseholdFormDialogState extends State<_HouseholdFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _amount;
  late final TextEditingController _quantity;
  late final TextEditingController _minQuantity;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  late HouseholdItemKind _kind;
  DateTime? _purchase;
  DateTime? _warranty;
  DateTime? _expiry;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _name = TextEditingController(text: current?.name);
    _brand = TextEditingController(text: current?.brandModel);
    _amount = TextEditingController(
        text: current?.purchaseAmountMinor == null
            ? ''
            : (current!.purchaseAmountMinor! / 100).toStringAsFixed(2));
    _quantity = TextEditingController(
        text: current == null ? '1' : _number(current.quantity));
    _minQuantity = TextEditingController(
        text: current?.minimumQuantity == null
            ? ''
            : _number(current!.minimumQuantity!));
    _unit = TextEditingController(text: current?.unit);
    _notes = TextEditingController(text: current?.notes);
    _kind = current?.itemKind == 'CONSUMABLE'
        ? HouseholdItemKind.consumable
        : HouseholdItemKind.durable;
    _purchase = current?.purchaseDate == null
        ? null
        : DateKeys.fromLocalDateKey(current!.purchaseDate!);
    _warranty = current?.warrantyEndDate == null
        ? null
        : DateKeys.fromLocalDateKey(current!.warrantyEndDate!);
    _expiry = current?.expiryDate == null
        ? null
        : DateKeys.fromLocalDateKey(current!.expiryDate!);
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _amount.dispose();
    _quantity.dispose();
    _minQuantity.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final digits = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

    return KeyboardSafeFormDialog(
      title: Text(current == null ? '添加家庭物品' : '编辑家庭物品'),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<HouseholdItemKind>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: HouseholdItemKind.durable,
                  icon: Icon(Icons.devices_other_outlined, size: 18),
                  label: Text('家电数码'),
                ),
                ButtonSegment(
                  value: HouseholdItemKind.consumable,
                  icon: Icon(Icons.shopping_basket_outlined, size: 18),
                  label: Text('日用消耗'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (values) =>
                  setState(() => _kind = values.first),
            ),
            if (_kind == HouseholdItemKind.consumable)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '记录库存与保质期，低于阈值或临期会提示补货。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            const _SectionLabel('基础信息'),
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(context, label: '名称'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? '请输入物品名称'
                  : null,
            ),
            const SizedBox(height: 12),
            if (_kind == HouseholdItemKind.durable)
              TextFormField(
                controller: _brand,
                decoration: _fieldDecoration(
                  context,
                  label: '品牌 / 型号',
                  hint: '选填',
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [digits],
                      decoration: _fieldDecoration(context, label: '库存数量'),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return '请填写数量';
                        final parsed = double.tryParse(text);
                        if (parsed == null || parsed < 0) return '数量无效';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: _fieldDecoration(
                        context,
                        label: '单位',
                        hint: '个 / 瓶',
                      ),
                    ),
                  ),
                ],
              ),
            const _SectionLabel('购买与期限'),
            if (_kind == HouseholdItemKind.durable) ...[
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [digits],
                decoration: _fieldDecoration(
                  context,
                  label: '购买金额',
                  suffix: '元',
                  hint: '选填',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  final parsed = double.tryParse(text);
                  if (parsed == null || parsed < 0) return '请输入有效金额';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '购买日期',
                      value: _purchase,
                      onChanged: (value) => setState(() => _purchase = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: '保修截止',
                      value: _warranty,
                      onChanged: (value) => setState(() => _warranty = value),
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextFormField(
                controller: _minQuantity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [digits],
                decoration: _fieldDecoration(
                  context,
                  label: '低于该数量提醒补货',
                  hint: '选填',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  final parsed = double.tryParse(text);
                  if (parsed == null || parsed < 0) return '请输入有效数量';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '购买日期',
                      value: _purchase,
                      onChanged: (value) => setState(() => _purchase = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: '保质期截止',
                      value: _expiry,
                      onChanged: (value) => setState(() => _expiry = value),
                    ),
                  ),
                ],
              ),
            ],
            const _SectionLabel('备注'),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: _fieldDecoration(
                context,
                label: '备注',
                hint: '序列号、购买渠道、售后电话…',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            final parsedAmount = double.tryParse(_amount.text.trim());
            Navigator.pop(
              context,
              HouseholdDraft(
                name: _name.text.trim(),
                brandModel: _brand.text,
                purchaseDate: _purchase,
                purchaseAmountMinor: parsedAmount == null
                    ? null
                    : (parsedAmount * 100).round(),
                warrantyEndDate: _warranty,
                itemKind: _kind,
                quantity: double.tryParse(_quantity.text) ?? 1,
                minimumQuantity: double.tryParse(_minQuantity.text.trim()),
                unit: _unit.text,
                expiryDate: _expiry,
                notes: _notes.text,
                sensitive: current?.sensitive ?? false,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 日期字段：与输入框同款的浅灰圆角块，两个可并排，
/// 比原来占两行的 ListTile 省一半高度，也不会出现"一个有底色一个没有"的不一致。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          barrierDismissible: false,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null
                        ? '未设置'
                        : DateFormat('yyyy-MM-dd').format(value!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null ? scheme.outline : null,
                    ),
                  ),
                ],
              ),
            ),
            if (value == null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              IconButton(
                tooltip: '清除',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
    );
  }
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
    final now = DateTime.now();
    return FutureBuilder<HouseholdItemEntry>(
        key: ValueKey(revision),
        future: repository.get(widget.itemId),
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final warranty = repository.warrantyState(item, now);
          final consumable = item.itemKind == 'CONSUMABLE'
              ? repository.consumableState(item, now)
              : null;
          final row = _ItemRow(
            item: item,
            now: now,
            warranty: warranty,
            consumable: consumable,
          );
          final badge = row.badge;

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
                                        title: Text('删除「${item.name}」？'),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error),
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.itemKind == 'CONSUMABLE'
                                ? Icons.shopping_basket_outlined
                                : Icons.devices_other_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.itemKind == 'CONSUMABLE' ? '日用消耗品' : '家电数码',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (badge != null)
                            _StatusBadge(text: badge.text, tone: badge.tone),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (item.itemKind == 'CONSUMABLE')
                        _InfoRow(
                          icon: Icons.inventory_2_outlined,
                          label: '当前库存',
                          value:
                              '${_number(item.quantity)}${item.unit ?? ''}${item.minimumQuantity == null ? '' : '（低于 ${_number(item.minimumQuantity!)} 提醒）'}',
                        ),
                      if ((item.brandModel ?? '').isNotEmpty)
                        _InfoRow(
                          icon: Icons.sell_outlined,
                          label: '品牌型号',
                          value: item.brandModel!,
                        ),
                      if (item.purchaseAmountMinor != null)
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          label: '购买金额',
                          value:
                              '¥${(item.purchaseAmountMinor! / 100).toStringAsFixed(2)}',
                        ),
                      if (item.purchaseDate != null)
                        _InfoRow(
                          icon: Icons.event_available_outlined,
                          label: '购买日期',
                          value: _shortDate(item.purchaseDate!),
                        ),
                      if (item.warrantyEndDate != null)
                        _InfoRow(
                          icon: Icons.verified_outlined,
                          label: '保修截止',
                          value: _shortDate(item.warrantyEndDate!),
                        ),
                      if (item.expiryDate != null)
                        _InfoRow(
                          icon: Icons.hourglass_bottom_outlined,
                          label: '保质期至',
                          value: _shortDate(item.expiryDate!),
                        ),
                      if ((item.notes ?? '').isNotEmpty)
                        _InfoRow(
                          icon: Icons.sticky_note_2_outlined,
                          label: '备注',
                          value: item.notes!,
                        ),
                      if (item.itemKind == 'CONSUMABLE') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await repository.adjustQuantity(item.id, -1);
                                  if (mounted) setState(() => revision++);
                                },
                                icon: const Icon(Icons.remove),
                                label: const Text('用掉 1'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () async {
                                  await repository.adjustQuantity(item.id, 1);
                                  if (mounted) setState(() => revision++);
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('补货 1'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await repository.addToShoppingList(item.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已加入购物清单')),
                              );
                            }
                          },
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('加入购物清单'),
                        ),
                      ],
                    ],
                  ),
                )),
                const SizedBox(height: 8),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
