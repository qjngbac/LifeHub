import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/features/life_records/data/anniversary_repository.dart';
import 'package:lifehub/features/life_records/presentation/life_record_dialogs.dart';

class AnniversariesPage extends ConsumerStatefulWidget {
  const AnniversariesPage({super.key});

  @override
  ConsumerState<AnniversariesPage> createState() => _AnniversariesPageState();
}

class _AnniversariesPageState extends ConsumerState<AnniversariesPage> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = AnniversaryRepository(ref.read(databaseProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('纪念日与倒数日')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(repository, null),
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
      body: FutureBuilder<List<AnniversaryEntry>>(
        key: ValueKey(revision),
        future: repository.listAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = [...snapshot.data!]..sort((left, right) => repository
              .daysUntil(left, DateTime.now())
              .compareTo(repository.daysUntil(right, DateTime.now())));
          if (values.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.celebration_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    '记录生日、纪念日和重要节点',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _edit(repository, null),
                    icon: const Icon(Icons.add),
                    label: const Text('添加第一个纪念日'),
                  ),
                ]),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: values.length,
            itemBuilder: (context, index) {
              final value = values[index];
              final date = DateKeys.fromLocalDateKey(value.date);
              final days = repository.daysUntil(value, DateTime.now());
              final relation = value.relationshipId != null;
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  leading: CircleAvatar(
                    backgroundColor: relation
                        ? const Color(0xFFFFDDE9)
                        : const Color(0xFFFFEDBF),
                    child: Icon(
                      relation ? Icons.favorite_outline : Icons.celebration,
                    ),
                  ),
                  title: Text(value.title),
                  subtitle: Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                    '${date.day.toString().padLeft(2, '0')}'
                    '${value.repeatYearly ? ' · 每年' : ''}',
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      days == 0
                          ? '就是今天'
                          : days > 0
                              ? '还有 $days 天'
                              : '已过 ${-days} 天',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _edit(repository, value);
                        } else {
                          _delete(repository, value);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('修改')),
                        PopupMenuItem(
                          value: 'delete',
                          child:
                              Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ]),
                  onTap: () => _edit(repository, value),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _edit(
    AnniversaryRepository repository,
    AnniversaryEntry? current,
  ) async {
    final draft = await showAnniversaryDialog(context, current: current);
    if (draft == null) return;
    if (current == null) {
      await repository.create(draft);
    } else {
      await repository.update(current.id, draft);
    }
    if (mounted) setState(() => revision++);
  }

  Future<void> _delete(
    AnniversaryRepository repository,
    AnniversaryEntry value,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('删除“${value.title}”？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await repository.delete(value.id);
    if (mounted) setState(() => revision++);
  }
}
