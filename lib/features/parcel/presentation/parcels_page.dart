import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/parcel/domain/parcel_text_parser.dart';
import 'package:lifehub/features/parcel/presentation/parcel_detail_page.dart';
import 'package:lifehub/features/parcel/presentation/parcel_form_style.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class ParcelsPage extends ConsumerStatefulWidget {
  const ParcelsPage({super.key});
  @override
  ConsumerState<ParcelsPage> createState() => _ParcelsPageState();
}

class _ParcelsPageState extends ConsumerState<ParcelsPage> {
  var revision = 0;
  var query = '';
  var statusFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final repository = ParcelRepository(ref.read(databaseProvider));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('快递与取件'),
        actions: [
          FutureBuilder<List<ParcelEntry>>(
            key: ValueKey('actions-$revision'),
            future: repository.pendingPickup(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? const [];
              if (pending.isEmpty) return const SizedBox.shrink();
              return TextButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: Text('全部已取(${pending.length})'),
                onPressed: () => _markAllCollected(repository, pending.length),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('快递'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: SearchBar(
              hintText: '搜索物品、单号或取件码',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ParcelEntry>>(
              key: ValueKey('$revision:$query'),
              future: repository.search(query),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                int statusPriority(String status) => switch (status) {
                      'READY' => 0,
                      'IN_TRANSIT' => 1,
                      'COLLECTED' => 2,
                      'RETURNED' => 3,
                      _ => 4,
                    };
                final allRows = List<ParcelEntry>.from(snapshot.data!)
                  ..sort((a, b) {
                    final pa = statusPriority(a.status);
                    final pb = statusPriority(b.status);
                    if (pa != pb) return pa.compareTo(pb);
                    return b.updatedAt.compareTo(a.updatedAt);
                  });
                final rows = statusFilter == 'ALL'
                    ? allRows
                    : allRows
                        .where((row) => row.status == statusFilter)
                        .toList();
                final readyCount = allRows
                    .where((row) => row.status == ParcelStatus.ready.dbValue)
                    .length;

                return Column(
                  children: [
                    _buildFilterBar(allRows),
                    const SizedBox(height: 6),
                    if ((statusFilter == 'ALL' || statusFilter == 'READY') &&
                        readyCount > 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '有 $readyCount 个包裹等待取件',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () =>
                                  _markAllCollected(repository, readyCount),
                              child: const Text('全部已取'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: rows.isEmpty
                          ? _EmptyState(
                              nothingAtAll: allRows.isEmpty,
                              filter: statusFilter,
                              onClearFilter: () =>
                                  setState(() => statusFilter = 'ALL'),
                              onAdd: () => _add(repository),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                              children: [
                                for (final row in rows)
                                  _buildCard(repository, row),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<ParcelEntry> allRows) {
    final counts = {
      'ALL': allRows.length,
      'READY':
          allRows.where((r) => r.status == ParcelStatus.ready.dbValue).length,
      'IN_TRANSIT': allRows
          .where((r) => r.status == ParcelStatus.inTransit.dbValue)
          .length,
      'COLLECTED': allRows
          .where((r) => r.status == ParcelStatus.collected.dbValue)
          .length,
      'RETURNED': allRows
          .where((r) => r.status == ParcelStatus.returned.dbValue)
          .length,
    };

    final filters = const [
      ('ALL', '全部'),
      ('READY', '待取件'),
      ('IN_TRANSIT', '运输中'),
      ('COLLECTED', '已完成'),
      ('RETURNED', '已退回'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final entry in filters) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                label: Text('${entry.$2} ${counts[entry.$1] ?? 0}'),
                selected: statusFilter == entry.$1,
                onSelected: (_) => setState(() => statusFilter = entry.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(ParcelRepository repository, ParcelEntry row) {
    final theme = Theme.of(context);
    final hint = pickupDeadlineHint(
      status: row.status,
      pickupDeadline: row.pickupDeadline,
      arrivedAt: row.arrivedAt,
      now: DateTime.now(),
    );
    final carrier = (row.carrier ?? '').trim();
    final notes = (row.notes ?? '').trim();
    final tracking = (row.trackingNumber ?? '').trim();
    final isReady = row.status == ParcelStatus.ready.dbValue;
    final isCollected = row.status == ParcelStatus.collected.dbValue;
    final isReturned = row.status == ParcelStatus.returned.dbValue;
    final actionable = row.status == ParcelStatus.inTransit.dbValue || isReady;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: isReady ? 1.5 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isReady
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isReady ? 1.2 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParcelDetailPage(parcelId: row.id),
            ),
          );
          if (mounted) setState(() => revision++);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (isReady
                              ? theme.colorScheme.primary
                              : isCollected
                                  ? Colors.green
                                  : isReturned
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isReady
                          ? Icons.markunread_mailbox_outlined
                          : isCollected
                              ? Icons.check_circle_outline
                              : isReturned
                                  ? Icons.undo_outlined
                                  : Icons.local_shipping_outlined,
                      size: 20,
                      color: isReady
                          ? theme.colorScheme.primary
                          : isCollected
                              ? Colors.green
                              : isReturned
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                    ),
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
                                row.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (hint != null) ...[
                              const SizedBox(width: 6),
                              ParcelStatusBadge(
                                  text: hint.text, tone: hint.tone),
                            ],
                          ],
                        ),
                        if (carrier.isNotEmpty || tracking.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (carrier.isNotEmpty)
                                Text(
                                  carrier,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (carrier.isNotEmpty && tracking.isNotEmpty)
                                Text(
                                  ' · ',
                                  style: TextStyle(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                              if (tracking.isNotEmpty)
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: tracking));
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text('已复制单号: $tracking'),
                                            duration:
                                                const Duration(seconds: 1),
                                          ),
                                        );
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            tracking,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme.outline,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.copy,
                                          size: 11,
                                          color: theme.colorScheme.outline,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (actionable)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () async {
                        await repository.advance(row.id);
                        await NotificationService.instance
                            .rebuildFuture(ref.read(databaseProvider));
                        if (mounted) setState(() => revision++);
                      },
                      child: Text(row.status == ParcelStatus.inTransit.dbValue
                          ? '到达取件点'
                          : '取件'),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: ParcelStatusBadge(
                        text: parcelStatusLabel(row.status),
                        tone: isReturned ? 2 : 0,
                      ),
                    ),
                ],
              ),
              if (row.pickupCode?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _pickupCodeChip(code: row.pickupCode!, isReady: isReady),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickupCodeChip({required String code, required bool isReady}) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('已复制取件码: $code'),
              duration: const Duration(seconds: 1),
            ),
          );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isReady ? 12 : 8,
          vertical: isReady ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: isReady
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: isReady
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2,
              size: isReady ? 20 : 16,
              color: isReady
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '取件码',
              style: TextStyle(
                fontSize: isReady ? 12 : 11,
                fontWeight: FontWeight.w600,
                color: isReady
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              code,
              style: TextStyle(
                fontSize: isReady ? 18 : 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: isReady
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.copy,
              size: isReady ? 14 : 12,
              color: isReady
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAllCollected(
    ParcelRepository repository,
    int count,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('全部标记已取'),
        content: Text('确定将当前全部 $count 个待取件包裹标记为“已取件”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await repository.markAllCollected();
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
    if (mounted) setState(() => revision++);
  }

  Future<void> _add(ParcelRepository repository) async {
    final draft = await showParcelForm(context);
    if (draft == null) return;
    await repository.create(draft);
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
    if (!mounted) return;
    setState(() => revision++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已添加「${draft.title}」')));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.nothingAtAll,
    required this.filter,
    required this.onClearFilter,
    required this.onAdd,
  });

  final bool nothingAtAll;
  final String filter;
  final VoidCallback onClearFilter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nothingAtAll) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 56,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 14),
              Text('还没有快递记录', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '添加后可按“运输中 → 待取件 → 已取件”更新状态',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('立即添加'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 14),
            Text('没有相关的快递记录', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              filter == 'READY' ? '当前没有待取件的包裹' : '换个筛选条件看看',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onClearFilter,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('查看全部'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<ParcelDraft?> showParcelForm(
  BuildContext context, {
  ParcelEntry? current,
}) async {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(text: current?.title);
  final info = TextEditingController(text: current?.notes);
  final code = TextEditingController(text: current?.pickupCode);
  final carrier = TextEditingController(text: current?.carrier);
  final tracking = TextEditingController(text: current?.trackingNumber);
  var status = current == null
      ? ParcelStatus.inTransit
      : ParcelStatus.values.firstWhere(
          (value) => value.dbValue == current.status,
          orElse: () => ParcelStatus.inTransit,
        );
  DateTime? deadline = current?.pickupDeadline == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(current!.pickupDeadline!);

  final accepted = await showDialog<ParcelDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '添加快递' : '编辑快递'),
        body: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final text =
                      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                  if (text == null || text.trim().isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(content: Text('剪贴板中没有内容')),
                        );
                    }
                    return;
                  }
                  final parsed = ParcelTextParser.parse(text);
                  final hasFound = parsed.pickupCode != null ||
                      parsed.trackingNumber != null ||
                      parsed.carrier != null;
                  setDialogState(() {
                    if (parsed.pickupCode != null) {
                      code.text = parsed.pickupCode!;
                      status = ParcelStatus.ready;
                    }
                    if (parsed.trackingNumber != null) {
                      tracking.text = parsed.trackingNumber!;
                    }
                    if (parsed.carrier != null && carrier.text.trim().isEmpty) {
                      carrier.text = parsed.carrier!;
                    }
                    if (title.text.trim().isEmpty) {
                      title.text = '${parsed.carrier ?? '包裹'}快递';
                    }
                    if (parsed.station != null && info.text.trim().isEmpty) {
                      info.text = parsed.station!;
                    } else if (info.text.trim().isEmpty) {
                      info.text = text.trim();
                    }
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(hasFound
                              ? '已自动识别：${parsed.carrier ?? '快递'}${parsed.pickupCode != null ? ' · 取件码 ${parsed.pickupCode}' : ''}'
                              : '已将剪贴板内容填入备注'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  }
                },
                icon: const Icon(Icons.content_paste),
                label: const Text('从剪贴板智能识别取件码 / 单号'),
              ),
              const ParcelSectionLabel('物品'),
              TextFormField(
                controller: title,
                autofocus: true,
                decoration: parcelFieldDecoration(context, label: '物品名称'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? '请输入物品名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: info,
                minLines: 1,
                maxLines: null,
                decoration: parcelFieldDecoration(
                  context,
                  label: '物品信息 / 驿站地址',
                  hint: '选填，例如“顺丰到付”或“北门菜鸟驿站”',
                ),
              ),
              const ParcelSectionLabel('物流'),
              TextFormField(
                controller: carrier,
                decoration: parcelFieldDecoration(
                  context,
                  label: '快递公司 / 驿站',
                  hint: '选填，例如 顺丰 / 菜鸟驿站 / 丰巢',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: tracking,
                decoration: parcelFieldDecoration(
                  context,
                  label: '快递单号',
                  hint: '选填，查件投诉会用到',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: code,
                decoration: parcelFieldDecoration(
                  context,
                  label: '取件码',
                  hint: '选填，例如 3-2-104 或 882910',
                ),
              ),
              const ParcelSectionLabel('状态与期限'),
              DropdownButtonFormField<ParcelStatus>(
                initialValue: status,
                decoration: parcelFieldDecoration(context, label: '状态'),
                items: const [
                  DropdownMenuItem(
                    value: ParcelStatus.inTransit,
                    child: Text('运输中'),
                  ),
                  DropdownMenuItem(
                    value: ParcelStatus.ready,
                    child: Text('待取件'),
                  ),
                  DropdownMenuItem(
                    value: ParcelStatus.collected,
                    child: Text('已取件'),
                  ),
                  DropdownMenuItem(
                    value: ParcelStatus.returned,
                    child: Text('已退回'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => status = value ?? status),
              ),
              const SizedBox(height: 12),
              ParcelDeadlineField(
                label: '取件截止（可选）',
                value: deadline,
                onChanged: (value) => setDialogState(() => deadline = value),
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
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                context,
                ParcelDraft(
                  title: title.text,
                  carrier: carrier.text,
                  trackingNumber: tracking.text,
                  pickupCode: code.text,
                  notes: info.text,
                  status: status,
                  pickupDeadline: deadline,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  info.dispose();
  code.dispose();
  carrier.dispose();
  tracking.dispose();
  return accepted;
}

String parcelStatusLabel(String value) => _status(value);
String _status(String value) => switch (value) {
      'IN_TRANSIT' => '运输中',
      'READY' => '待取件',
      'COLLECTED' => '已取件',
      'RETURNED' => '已退回',
      _ => '已归档'
    };
