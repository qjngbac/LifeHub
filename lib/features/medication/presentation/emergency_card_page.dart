import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/medication/data/medication_repository.dart';
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
          label: const Text('编辑')),
      body: FutureBuilder<EmergencyCardEntry?>(
        key: ValueKey(revision),
        future: repository.emergencyCard(),
        builder: (context, snapshot) {
          final value = snapshot.data;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        Text('仅用于保存你自己提供的紧急信息，不提供诊断、剂量或治疗建议。紧急情况请联系当地急救服务。'))),
            if (value == null)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('还没有急救卡。所有字段都可选，并只保存在本机。')))
            else ...[
              _field('姓名', value.name),
              _field(
                '出生年月',
                value.birthDate == null
                    ? null
                    : _formatDate(DateKeys.fromLocalDateKey(value.birthDate!)),
              ),
              _field('血型', value.bloodType),
              _field('过敏信息', value.allergies),
              _field('既往情况', value.conditions),
              _field('正在使用的药物', value.medications),
              _field('紧急联系人', value.emergencyContacts),
              _field('备注', value.notes),
            ],
          ]);
        },
      ),
    );
  }

  Widget _field(String title, String? value) => Card(
      child: ListTile(
          title: Text(title),
          subtitle: Text(value?.trim().isNotEmpty == true ? value! : '未填写')));

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
    final contacts = TextEditingController(text: current?.emergencyContacts);
    final notes = TextEditingController(text: current?.notes);
    final save = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => KeyboardSafeFormDialog(
                  title: const Text('编辑急救卡'),
                  body: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: '姓名')),
                    TextField(
                      controller: birthDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: '出生年月',
                        hintText: '未填写',
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
                                  initialDate:
                                      birthDate ?? DateTime(2000, 1, 1),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                  initialDatePickerMode: DatePickerMode.year,
                                  barrierDismissible: false,
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    birthDate = picked;
                                    birthDateController.text =
                                        _formatDate(picked);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextField(
                        controller: blood,
                        decoration: const InputDecoration(labelText: '血型')),
                    TextField(
                        controller: allergies,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: '过敏信息')),
                    TextField(
                        controller: conditions,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: '既往情况')),
                    TextField(
                        controller: medications,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: '正在使用的药物（用户自填）')),
                    TextField(
                        controller: contacts,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: '紧急联系人')),
                    TextField(
                        controller: notes,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: '备注')),
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
    if (save == true) {
      await repository.saveEmergencyCard(EmergencyCardDraft(
          name: name.text,
          birthDate: birthDate,
          bloodType: blood.text,
          allergies: allergies.text,
          conditions: conditions.text,
          medications: medications.text,
          emergencyContacts: contacts.text,
          notes: notes.text));
      if (mounted) setState(() => revision++);
    }
    for (final controller in [
      name,
      birthDateController,
      blood,
      allergies,
      conditions,
      medications,
      contacts,
      notes
    ]) {
      controller.dispose();
    }
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
