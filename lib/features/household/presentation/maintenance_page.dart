import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/features/household/data/maintenance_repository.dart';

class MaintenancePage extends ConsumerStatefulWidget {
  const MaintenancePage({super.key});
  @override
  ConsumerState<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends ConsumerState<MaintenancePage> {
  var revision = 0;
  @override
  Widget build(BuildContext context) {
    final repository = MaintenanceRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('周期维护')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(repository),
        icon: const Icon(Icons.add),
        label: const Text('维护计划'),
      ),
      body: FutureBuilder(
        key: ValueKey(revision),
        future: repository.list(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('还没有周期维护计划'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.home_repair_service_outlined),
                  title: Text(row.title),
                  subtitle: Text(
                      '下次 ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(row.nextDueAt))} · 每 ${row.intervalDays} 天'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'task') {
                        await repository.ensureCurrentTask(row.id);
                      }
                      if (value == 'done') {
                        await repository.completePlan(row.id);
                      }
                      if (mounted) setState(() => revision++);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'task', child: Text('生成维护任务')),
                      PopupMenuItem(value: 'done', child: Text('完成本次维护')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(MaintenanceRepository repository) async {
    final title = TextEditingController();
    final days = TextEditingController(text: '30');
    var due = DateTime.now().add(const Duration(days: 30));
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加维护计划'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '维护事项')),
            TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '间隔天数')),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('首次到期'),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(due)),
                onTap: () async {
                  final value = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: due,
                      barrierDismissible: false);
                  if (value != null) setDialogState(() => due = value);
                }),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'))
          ],
        ),
      ),
    );
    if (accepted == true && title.text.trim().isNotEmpty) {
      await repository.create(MaintenanceDraft(
          title: title.text,
          intervalDays: int.parse(days.text),
          nextDueAt: due));
      if (mounted) setState(() => revision++);
    }
    title.dispose();
    days.dispose();
  }
}
