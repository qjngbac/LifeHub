import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/attachment/presentation/attachment_panel.dart';
import 'package:lifehub/features/credentials/data/credential_repository.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class CredentialsPage extends ConsumerStatefulWidget {
  const CredentialsPage({super.key});
  @override
  ConsumerState<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends ConsumerState<CredentialsPage> {
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = CredentialRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('证件到期提醒')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(repository),
          icon: const Icon(Icons.add),
          label: const Text('证件')),
      body: FutureBuilder<List<CredentialRecordEntry>>(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('只建议填写名称和号码提示，不保存完整证件号'));
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(14),
                    child:
                        Text('号码字段用于“尾号 1234”等提示，请勿填写完整证件号码。到期提醒使用本地系统通知。'))),
            for (final value in snapshot.data!)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(value.name),
                  subtitle: Text(_credentialSubtitle(value)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _CredentialDetail(recordId: value.id),
                      ),
                    );
                    if (mounted) setState(() => revision++);
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _edit(CredentialRepository repository) async {
    final draft = await _credentialForm(context);
    if (draft == null) return;
    await repository.create(draft);
    await _refreshNotifications();
    if (mounted) setState(() => revision++);
  }

  Future<void> _refreshNotifications() =>
      NotificationService.instance.rebuildFuture(ref.read(databaseProvider));
}

class _CredentialDetail extends ConsumerStatefulWidget {
  const _CredentialDetail({required this.recordId});
  final String recordId;
  @override
  ConsumerState<_CredentialDetail> createState() => _CredentialDetailState();
}

class _CredentialDetailState extends ConsumerState<_CredentialDetail> {
  int revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = CredentialRepository(ref.read(databaseProvider));
    return FutureBuilder<CredentialRecordEntry>(
      key: ValueKey(revision),
      future: repository.get(widget.recordId),
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(title: Text(value.name), actions: [
            PopupMenuButton<String>(
              onSelected: (action) => _action(repository, value, action),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('删除',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              ],
            )
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Column(children: [
                ListTile(
                    title: const Text('号码提示'),
                    subtitle: Text(value.numberHint ?? '未填写')),
                ListTile(
                    title: const Text('到期日期'),
                    subtitle: Text(value.expiryDate == null
                        ? '未设置'
                        : DateFormat('yyyy年M月d日').format(
                            DateKeys.fromLocalDateKey(value.expiryDate!)))),
                if (value.expiryDate != null)
                  ListTile(
                      title: const Text('系统提醒'),
                      subtitle: Text('提前 ${value.reminderDays} 天提醒')),
                if (value.notes != null)
                  ListTile(
                      title: const Text('备注'), subtitle: Text(value.notes!)),
              ]),
            ),
            AttachmentPanel(
                entityType: 'CREDENTIAL', entityId: value.id, sensitive: true),
          ]),
        );
      },
    );
  }

  Future<void> _action(CredentialRepository repository,
      CredentialRecordEntry record, String action) async {
    if (action == 'edit') {
      final draft = await _credentialForm(context, current: record);
      if (draft == null) return;
      await repository.update(record.id, draft);
      await _refreshNotifications();
      if (mounted) setState(() => revision++);
      return;
    }
    final yes = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('删除“${record.name}”？'),
            content: const Text('对应的到期系统通知也会取消。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
    if (!yes) return;
    await repository.delete(record.id);
    await _refreshNotifications();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _refreshNotifications() =>
      NotificationService.instance.rebuildFuture(ref.read(databaseProvider));
}

Future<CredentialDraft?> _credentialForm(BuildContext context,
    {CredentialRecordEntry? current}) async {
  final name = TextEditingController(text: current?.name);
  final hint = TextEditingController(text: current?.numberHint);
  final holder = TextEditingController(text: current?.holder);
  final notes = TextEditingController(text: current?.notes);
  final days = TextEditingController(text: '${current?.reminderDays ?? 30}');
  DateTime? expiry = current?.expiryDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.expiryDate!);
  var reminderEnabled = current == null ? true : current.reminderDays >= 0;
  final result = await showDialog<CredentialDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '添加证件提醒' : '编辑证件提醒'),
        body: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '证件名称 *')),
          TextField(
              controller: hint,
              decoration: const InputDecoration(labelText: '号码提示（如尾号 1234）')),
          TextField(
              controller: holder,
              decoration: const InputDecoration(labelText: '持有人（可选）')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('到期日期'),
            subtitle: Text(expiry == null
                ? '未设置'
                : DateFormat('yyyy年M月d日').format(expiry!)),
            trailing: expiry == null
                ? const Icon(Icons.event_outlined)
                : IconButton(
                    onPressed: () => setDialogState(() => expiry = null),
                    icon: const Icon(Icons.clear)),
            onTap: () async {
              final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      expiry ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2200),
                  barrierDismissible: false);
              if (picked != null) setDialogState(() => expiry = picked);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('到期前系统提醒'),
            subtitle: Text(expiry == null ? '请先设置到期日期' : '使用本地系统通知'),
            value: reminderEnabled && expiry != null,
            onChanged: expiry == null
                ? null
                : (value) => setDialogState(() => reminderEnabled = value),
          ),
          if (reminderEnabled && expiry != null)
            TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '提前多少天提醒')),
          TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注（可选）')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              final reminderDays = reminderEnabled && expiry != null
                  ? int.tryParse(days.text.trim()) ?? 30
                  : -1;
              Navigator.pop(
                  context,
                  CredentialDraft(
                      name: name.text,
                      holder: holder.text,
                      numberHint: hint.text,
                      expiryDate: expiry,
                      reminderDays: reminderDays,
                      notes: notes.text));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  for (final controller in [name, hint, holder, notes, days]) {
    controller.dispose();
  }
  return result;
}

String _credentialSubtitle(CredentialRecordEntry value) {
  final parts = <String>[];
  if (value.numberHint != null) parts.add(value.numberHint!);
  if (value.expiryDate == null) {
    parts.add('未设置到期日期');
  } else {
    final expiry = DateKeys.fromLocalDateKey(value.expiryDate!);
    final today = DateTime.now();
    final days = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    parts.add('到期 ${DateFormat('yyyy年M月d日').format(expiry)}');
    parts.add(days >= 0 ? '还有 $days 天' : '已过期 ${-days} 天');
  }
  return parts.join(' · ');
}
