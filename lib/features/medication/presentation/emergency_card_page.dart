import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
import 'package:lifehub/features/medication/presentation/medication_form_style.dart';
import 'package:lifehub/shared/ui/keyboard_safe_form_dialog.dart';

class EmergencyCardPage extends ConsumerStatefulWidget {
  const EmergencyCardPage({super.key});
  @override
  ConsumerState<EmergencyCardPage> createState() => _EmergencyCardPageState();
}

class _EmergencyCardPageState extends ConsumerState<EmergencyCardPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = MedicationRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('本地急救卡')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repository),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('编辑'),
      ),
      body: FutureBuilder<EmergencyCardEntry?>(
        key: ValueKey(revision),
        future: repository.emergencyCard(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('急救卡加载失败，请稍后重试'));
          }
          if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final value = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              const _EmergencyNotice(),
              if (value == null || _isEmpty(value))
                _EmptyCard(onPressed: () => _edit(repository))
              else
                ..._buildCard(context, value),
            ],
          );
        },
      ),
    );
  }

  /// 急救卡的全部字段都是可选的，全空时视为"还没填"。
  bool _isEmpty(EmergencyCardEntry value) =>
      _clean(value.name) == null &&
      value.birthDate == null &&
      _clean(value.bloodType) == null &&
      _clean(value.allergies) == null &&
      _clean(value.conditions) == null &&
      _clean(value.medications) == null &&
      _clean(value.emergencyContacts) == null &&
      _clean(value.notes) == null;

  /// 只渲染"有内容"的字段，并把没填的字段汇总成一行，
  /// 避免出现 8 张卡片里 6 张写着"未填写"的卡片墙。
  List<Widget> _buildCard(BuildContext context, EmergencyCardEntry value) {
    final theme = Theme.of(context);
    final name = _clean(value.name);
    final blood = _clean(value.bloodType);
    final contact =
        MedicationRepository.splitEmergencyContact(value.emergencyContacts);

    final health = <Widget>[
      if (_clean(value.allergies) != null)
        _InfoRow(
          icon: Icons.warning_amber_rounded,
          label: '过敏信息',
          value: value.allergies!.trim(),
          emphasize: true,
        ),
      if (_clean(value.conditions) != null)
        _InfoRow(
          icon: Icons.monitor_heart_outlined,
          label: '既往情况',
          value: value.conditions!.trim(),
        ),
      if (_clean(value.medications) != null)
        _InfoRow(
          icon: Icons.medication_outlined,
          label: '正在使用',
          value: value.medications!.trim(),
        ),
    ];

    final missing = <String>[
      if (name == null) '姓名',
      if (value.birthDate == null) '出生年月',
      if (blood == null) '血型',
      if (_clean(value.allergies) == null) '过敏信息',
      if (_clean(value.conditions) == null) '既往情况',
      if (_clean(value.medications) == null) '正在使用药物',
      if (_clean(value.emergencyContacts) == null) '紧急联系人',
      if (_clean(value.notes) == null) '备注',
    ];

    return [
      // ① 概览：急救时最先要看的三件事
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.contact_emergency_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? '未填写姓名',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // 血型单独做成醒目的块：急救现场最需要一眼看到
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: blood == null
                                ? theme.colorScheme.surfaceContainerHighest
                                : theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bloodtype_outlined,
                                size: 14,
                                color: blood == null
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                blood ?? '未填血型',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: blood == null
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (value.birthDate != null)
                          MedicationMiniTag(
                            // 出生年月必须是独立的 Text，方便"复制/朗读"时单独取用
                            text: _formatDate(
                              DateKeys.fromLocalDateKey(value.birthDate!),
                            ),
                            icon: Icons.cake_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ② 健康信息
      const SizedBox(height: 4),
      _SectionCard(
        title: '健康信息',
        icon: Icons.health_and_safety_outlined,
        child: health.isEmpty
            ? const _SectionEmpty(text: '还没有填写过敏、既往情况或正在使用的药物')
            : Column(children: health),
      ),

      // ③ 紧急联系人（身份与电话分开显示，电话可一键复制）
      _SectionCard(
        title: '紧急联系人',
        icon: Icons.call_outlined,
        child: contact.name.isEmpty && contact.phone.isEmpty
            ? const _SectionEmpty(text: '建议填写至少一位联系人及其电话')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (contact.name.isNotEmpty)
                    _InfoRow(
                      icon: Icons.person_outline,
                      label: '身份',
                      value: contact.name,
                    ),
                  if (contact.phone.isNotEmpty)
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      label: '电话',
                      value: contact.phone,
                    ),
                  if (contact.phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: contact.phone));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('电话已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('复制电话'),
                    ),
                  ],
                ],
              ),
      ),

      // ④ 备注
      if (_clean(value.notes) != null)
        _SectionCard(
          title: '备注',
          icon: Icons.sticky_note_2_outlined,
          child: SelectableText(
            value.notes!.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),

      // ⑤ 未填写项汇总（替代 8 张"未填写"卡片）
      if (missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 14, left: 4, right: 4),
          child: Text(
            '未填写：${missing.join('、')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.5,
            ),
          ),
        ),
    ];
  }

  Future<void> _edit(MedicationRepository repository) async {
    final current = await repository.emergencyCard();
    if (!mounted) return;
    final name = TextEditingController(text: current?.name);
    DateTime? birthDate = current?.birthDate == null
        ? null
        : DateKeys.fromLocalDateKey(current!.birthDate!);
    final birthDateController = TextEditingController(
      text: birthDate == null ? null : _formatDate(birthDate),
    );
    final blood = TextEditingController(text: current?.bloodType);
    final allergies = TextEditingController(text: current?.allergies);
    final conditions = TextEditingController(text: current?.conditions);
    final medications = TextEditingController(text: current?.medications);
    final contact = MedicationRepository.splitEmergencyContact(
      current?.emergencyContacts,
    );
    final contactName = TextEditingController(text: contact.name);
    final contactPhone = TextEditingController(text: contact.phone);
    final notes = TextEditingController(text: current?.notes);
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => KeyboardSafeFormDialog(
          title: const Text('编辑急救卡'),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '所有字段都可选，只保存在本机，用于紧急情况下让别人快速了解你。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      height: 1.5,
                    ),
              ),
              const MedicationSectionLabel('基本信息'),
              TextField(
                controller: name,
                decoration: medicationFieldDecoration(context, label: '姓名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: birthDateController,
                readOnly: true,
                decoration: medicationFieldDecoration(
                  context,
                  label: '出生年月',
                  hint: '未填写',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (birthDate != null)
                        IconButton(
                          tooltip: '清除',
                          onPressed: () => setDialogState(() {
                            birthDate = null;
                            birthDateController.clear();
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: '选择日期',
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: birthDate ?? DateTime(2000, 1, 1),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                            initialDatePickerMode: DatePickerMode.year,
                            barrierDismissible: false,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              birthDate = picked;
                              birthDateController.text = _formatDate(picked);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: blood,
                decoration: medicationFieldDecoration(
                  context,
                  label: '血型',
                  hint: '例如 O 型 / AB 型',
                ),
              ),
              // 血型快捷选择：急救场合没人愿意在手机上打字
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in const [
                      'A 型',
                      'B 型',
                      'O 型',
                      'AB 型',
                      'Rh 阴性',
                    ])
                      ActionChip(
                        label: Text(option),
                        onPressed: () =>
                            setDialogState(() => blood.text = option),
                      ),
                  ],
                ),
              ),
              const MedicationSectionLabel('健康信息'),
              // 这些字段默认只占一行，内容多了（换行/长文本）会自动长高
              TextField(
                controller: allergies,
                minLines: 1,
                maxLines: null,
                decoration: medicationFieldDecoration(
                  context,
                  label: '过敏信息',
                  hint: '药物、食物、接触性过敏',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: conditions,
                minLines: 1,
                maxLines: null,
                decoration: medicationFieldDecoration(
                  context,
                  label: '既往情况',
                  hint: '慢性病、手术史等',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: medications,
                minLines: 1,
                maxLines: null,
                decoration: medicationFieldDecoration(
                  context,
                  label: '正在使用的药物（用户自填）',
                ),
              ),
              const MedicationSectionLabel('紧急联系人'),
              TextField(
                controller: contactName,
                decoration: medicationFieldDecoration(
                  context,
                  label: '身份（姓名）',
                  hint: '例如 母亲 / 王医生',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contactPhone,
                keyboardType: TextInputType.phone,
                decoration: medicationFieldDecoration(
                  context,
                  label: '电话',
                  hint: '选填',
                ),
              ),
              const MedicationSectionLabel('备注'),
              TextField(
                controller: notes,
                minLines: 1,
                maxLines: null,
                decoration: medicationFieldDecoration(
                  context,
                  label: '备注',
                  hint: '医院、主治医生、保险等',
                ),
              ),
            ],
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
    if (save == true) {
      await repository.saveEmergencyCard(
        EmergencyCardDraft(
          name: name.text,
          birthDate: birthDate,
          bloodType: blood.text,
          allergies: allergies.text,
          conditions: conditions.text,
          medications: medications.text,
          emergencyContacts: MedicationRepository.joinEmergencyContact(
            contactName.text,
            contactPhone.text,
          ),
          notes: notes.text,
        ),
      );
      if (!mounted) return;
      setState(() => revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('急救卡已保存')),
      );
    }
    for (final controller in [
      name,
      birthDateController,
      blood,
      allergies,
      conditions,
      medications,
      contactName,
      contactPhone,
      notes,
    ]) {
      controller.dispose();
    }
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        emphasize ? theme.colorScheme.error : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                fontWeight: emphasize ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部说明：原来是整块纯红卡片，视觉上像报错；改成中性色可展开提示。
class _EmergencyNotice extends StatefulWidget {
  const _EmergencyNotice();

  @override
  State<_EmergencyNotice> createState() => _EmergencyNoticeState();
}

class _EmergencyNoticeState extends State<_EmergencyNotice> {
  static const _text =
      '仅用于保存你自己提供的紧急信息，不提供诊断、剂量或治疗建议。紧急情况请联系当地急救服务。';

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _text,
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contact_emergency_outlined,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 14),
            Text('还没有急救卡', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '填好血型、过敏与紧急联系人，\n紧急时别人可以一眼看到关键信息。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('填写急救卡'),
            ),
          ],
        ),
      ),
    );
  }
}
