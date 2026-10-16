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
  String? selectedHolder;

  @override
  Widget build(BuildContext context) {
    final repository = CredentialRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('证件到期提醒')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repository),
        icon: const Icon(Icons.add),
        label: const Text('证件'),
      ),
      body: FutureBuilder<List<CredentialRecordEntry>>(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allItems = snapshot.data!;
          if (allItems.isEmpty) {
            return const Center(child: Text('只建议填写名称和号码提示，不保存完整证件号'));
          }

          final holders =
              allItems
                  .map((e) => e.holder?.trim())
                  .where((h) => h != null && h.isNotEmpty)
                  .cast<String>()
                  .toSet()
                  .toList()
                ..sort();

          final items = selectedHolder == null
              ? allItems
              : allItems
                    .where((e) => e.holder?.trim() == selectedHolder)
                    .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            children: [
              const Card(
                child: ExpansionTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  dense: true,
                  tilePadding: EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(Icons.shield_outlined, size: 20),
                  title: Text('仅记录尾号，使用本机提醒', style: TextStyle(fontSize: 12.5)),
                  childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    Text('号码字段用于“尾号 1234”等提示，请勿填写完整证件号码。到期提醒使用本地系统通知。'),
                  ],
                ),
              ),
              if (holders.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('全部持有人'),
                        selected: selectedHolder == null,
                        onSelected: (_) =>
                            setState(() => selectedHolder = null),
                      ),
                      for (final h in holders) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(h),
                          selected: selectedHolder == h,
                          onSelected: (_) => setState(() => selectedHolder = h),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final value in items)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _CredentialDetail(recordId: value.id),
                        ),
                      );
                      if (mounted) setState(() => revision++);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.badge_outlined,
                                  size: 21,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  value.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _credentialSubtitle(value),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _expiryBadge(context, value),
                              if (value.holder?.isNotEmpty == true)
                                Text(
                                  '持有人 ${value.holder}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (value.numberHint?.isNotEmpty == true)
                                Text(
                                  value.numberHint!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(CredentialRepository repository) async {
    final database = ref.read(databaseProvider);
    final draft = await _credentialForm(context);
    if (draft == null) return;
    await repository.create(draft);
    await NotificationService.instance.rebuildFuture(database);
    if (mounted) setState(() => revision++);
  }
}

Widget _expiryBadge(BuildContext context, CredentialRecordEntry value) {
  if (value.expiryDate == null) {
    return const Chip(
      label: Text('长期/未设', style: TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
  final expiry = DateKeys.fromLocalDateKey(value.expiryDate!);
  final today = DateTime.now();
  final days = DateTime(expiry.year, expiry.month, expiry.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;

  if (days < 0) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '已过期 ${-days} 天',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  } else if (days <= 30) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        days == 0 ? '今天到期' : '$days 天后到期',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.deepOrange,
        ),
      ),
    );
  } else {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '还有 $days 天',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.green,
        ),
      ),
    );
  }
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
                if (value.holder?.isNotEmpty == true)
                  ListTile(
                      title: const Text('持有人'),
                      subtitle: Text(value.holder!)),
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
                if (value.notes != null && value.notes!.isNotEmpty)
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
      final database = ref.read(databaseProvider);
      final draft = await _credentialForm(context, current: record);
      if (draft == null) return;
      await repository.update(record.id, draft);
      await NotificationService.instance.rebuildFuture(database);
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

Future<CredentialDraft?> _credentialForm(
  BuildContext context, {
  CredentialRecordEntry? current,
}) async {
  final name = TextEditingController(text: current?.name);
  final hint = TextEditingController(text: current?.numberHint);
  final holder = TextEditingController(text: current?.holder);
  final notes = TextEditingController(text: current?.notes);
  final days = TextEditingController(text: '${current?.reminderDays ?? 30}');
  DateTime? expiry = current?.expiryDate == null
      ? null
      : DateKeys.fromLocalDateKey(current!.expiryDate!);
  var reminderEnabled = current == null ? true : current.reminderDays >= 0;
  String? nameError;

  final templates = const [
    ('居民身份证', 90, '身份证'),
    ('机动车驾驶证', 90, '驾驶证'),
    ('普通护照', 180, '护照'),
    ('往来港澳通行证', 90, '港澳通行证'),
    ('居住证', 30, '居住证'),
    ('社会保障卡', 60, '社保卡'),
  ];

  final route = DialogRoute<CredentialDraft>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => KeyboardSafeFormDialog(
        title: Text(current == null ? '添加证件' : '编辑证件'),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('常用模板', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: templates
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$3, style: const TextStyle(fontSize: 13)),
                      selected: name.text == t.$1,
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      onSelected: (selected) {
                        if (!selected) return;
                        setDialogState(() {
                          name.text = t.$1;
                          days.text = '${t.$2}';
                          reminderEnabled = true;
                          nameError = null;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text('基本信息', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: name,
              autofocus: current == null,
              onChanged: (_) => setDialogState(() => nameError = null),
              decoration: _credentialFieldDecoration(
                context,
                '证件名称',
                hintText: '证件、服务或其他到期事项',
                errorText: nameError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hint,
              decoration: _credentialFieldDecoration(
                context,
                '号码提示',
                hintText: '如尾号 1234',
              ).copyWith(helperText: '勿填写完整号码', helperMaxLines: 2),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: holder,
              decoration: _credentialFieldDecoration(context, '持有人（可选）'),
            ),
            const SizedBox(height: 16),
            Text('到期与提醒', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                leading: Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('到期日期'),
                subtitle: Text(
                  expiry == null
                      ? '未设置'
                      : DateFormat('yyyy-MM-dd').format(expiry!),
                ),
                trailing: expiry == null
                    ? const Icon(Icons.chevron_right, size: 20)
                    : IconButton(
                        tooltip: '清除到期日期',
                        onPressed: () => setDialogState(() => expiry = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        expiry ?? DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2200),
                    barrierDismissible: false,
                  );
                  if (picked != null && context.mounted) {
                    setDialogState(() => expiry = picked);
                  }
                },
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '到期前系统提醒',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Text(
                expiry == null ? '设置日期后可开启' : '通过本机通知提醒',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: reminderEnabled && expiry != null,
              onChanged: expiry == null
                  ? null
                  : (value) => setDialogState(() => reminderEnabled = value),
            ),
            if (reminderEnabled && expiry != null)
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: _credentialFieldDecoration(
                  context,
                  '提前提醒',
                  suffixText: '天',
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: _credentialFieldDecoration(context, '备注（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                setDialogState(() => nameError = '请输入证件名称');
                return;
              }
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
                  notes: notes.text,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  for (final controller in [name, hint, holder, notes, days]) {
    controller.dispose();
  }
  return result;
}

String _credentialSubtitle(CredentialRecordEntry value) {
  if (value.expiryDate == null) {
    return '未设置到期日期';
  }
  final expiry = DateKeys.fromLocalDateKey(value.expiryDate!);
  return '${DateFormat('yyyy-MM-dd').format(expiry)} 到期';
}

InputDecoration _credentialFieldDecoration(
  BuildContext context,
  String label, {
  String? hintText,
  String? errorText,
  String? suffixText,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
  );
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    errorText: errorText,
    suffixText: suffixText,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
  );
}
