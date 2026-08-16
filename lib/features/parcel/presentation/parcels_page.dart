import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/parcel/data/parcel_repository.dart';
import 'package:lifehub/features/parcel/domain/parcel_text_parser.dart';
import 'package:lifehub/features/parcel/presentation/parcel_detail_page.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class ParcelsPage extends ConsumerStatefulWidget {
  const ParcelsPage({super.key});
  @override
  ConsumerState<ParcelsPage> createState() => _ParcelsPageState();
}

class _ParcelsPageState extends ConsumerState<ParcelsPage> {
  var revision = 0;
  var query = '';

  @override
  Widget build(BuildContext context) {
    final repository = ParcelRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('快递与取件')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(repository),
          icon: const Icon(Icons.add),
          label: const Text('快递')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
              hintText: '在快递模块内搜索',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => query = value)),
        ),
        Expanded(
          child: FutureBuilder(
            key: ValueKey('$revision:$query'),
            future: repository.search(query),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('还没有快递记录'),
                      SizedBox(height: 6),
                      Text('添加后可按“运输中 → 待取件 → 已取件”更新状态'),
                    ],
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(row.title),
                        subtitle: Text(
                            [
                              _status(row.status),
                              if (row.notes != null) row.notes!,
                              if (row.pickupDeadline != null)
                                '最晚 ${DateFormat('M月d日 HH:mm').format(DateTime.fromMillisecondsSinceEpoch(row.pickupDeadline!))}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: _advanceButton(repository, row),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ParcelDetailPage(parcelId: row.id),
                            ),
                          );
                          if (mounted) setState(() => revision++);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _advanceButton(ParcelRepository repository, ParcelEntry row) {
    if (row.status == ParcelStatus.collected.dbValue) {
      return const Chip(label: Text('已完成'));
    }
    return FilledButton.tonal(
      onPressed: () async {
        await repository.advance(row.id);
        await NotificationService.instance
            .rebuildFuture(ref.read(databaseProvider));
        if (mounted) setState(() => revision++);
      },
      child:
          Text(row.status == ParcelStatus.inTransit.dbValue ? '到达取件点' : '已取件'),
    );
  }

  Future<void> _add(ParcelRepository repository) async {
    final draft = await showParcelForm(context);
    if (draft == null) return;
    await repository.create(draft);
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
    if (mounted) setState(() => revision++);
  }
}

Future<ParcelDraft?> showParcelForm(BuildContext context,
    {ParcelEntry? current}) async {
  final title = TextEditingController(text: current?.title);
  final info = TextEditingController(text: current?.notes);
  final code = TextEditingController(text: current?.pickupCode);
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
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton.icon(
            onPressed: () async {
              final text =
                  (await Clipboard.getData(Clipboard.kTextPlain))?.text;
              if (text == null || text.trim().isEmpty) return;
              final parsed = ParcelTextParser.parse(text);
              setDialogState(() {
                code.text = parsed.pickupCode ?? code.text;
                info.text = text.trim();
              });
            },
            icon: const Icon(Icons.content_paste),
            label: const Text('从剪贴板提取候选信息'),
          ),
          TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '物品名称 *')),
          TextField(
              controller: info,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '物品信息（可选）')),
          TextField(
              controller: code,
              decoration: const InputDecoration(labelText: '取件码（可选）')),
          DropdownButtonFormField<ParcelStatus>(
            initialValue: status,
            decoration: const InputDecoration(labelText: '状态'),
            items: const [
              DropdownMenuItem(
                  value: ParcelStatus.inTransit, child: Text('运输中')),
              DropdownMenuItem(value: ParcelStatus.ready, child: Text('待取件')),
              DropdownMenuItem(
                  value: ParcelStatus.collected, child: Text('已取件')),
            ],
            onChanged: (value) =>
                setDialogState(() => status = value ?? status),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('取件截止（可选）'),
            subtitle: Text(deadline == null
                ? '未设置'
                : DateFormat('yyyy-MM-dd HH:mm').format(deadline!)),
            trailing: deadline == null
                ? const Icon(Icons.event_outlined)
                : IconButton(
                    onPressed: () => setDialogState(() => deadline = null),
                    icon: const Icon(Icons.clear)),
            onTap: () async {
              final initial =
                  deadline ?? DateTime.now().add(const Duration(days: 1));
              final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                  initialDate: initial,
                  barrierDismissible: false);
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(initial),
                  barrierDismissible: false);
              if (time != null) {
                setDialogState(() => deadline = DateTime(
                    date.year, date.month, date.day, time.hour, time.minute));
              }
            },
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(
                  context,
                  ParcelDraft(
                      title: title.text,
                      pickupCode: code.text,
                      notes: info.text,
                      status: status,
                      pickupDeadline: deadline));
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
