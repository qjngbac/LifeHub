import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/features/reminder/data/reminder_repository.dart';

class ReminderCenterPage extends ConsumerStatefulWidget {
  const ReminderCenterPage({super.key});

  @override
  ConsumerState<ReminderCenterPage> createState() => _ReminderCenterPageState();
}

class _ReminderCenterPageState extends ConsumerState<ReminderCenterPage> {
  @override
  Widget build(BuildContext context) {
    ref.watch(refreshProvider);
    final repository = ReminderRepository(
      ref.read(databaseProvider),
      notifications: NotificationService.instance,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('提醒中心')),
      body: FutureBuilder<List<ReminderView>>(
        future: repository.listWindow(now: DateTime.now()),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('提醒加载失败'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final reminders = snapshot.data!;
          if (reminders.isEmpty) {
            return const _EmptyReminders();
          }
          final missed = reminders.where((item) => item.missed).toList();
          final future = reminders.where((item) => !item.missed).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.notifications_active_outlined),
                  title: Text('未来 7 天提醒'),
                  subtitle: Text('系统权限可在上一级“通知权限与提醒”中检查'),
                ),
              ),
              if (missed.isNotEmpty) ...[
                const _SectionTitle('已经错过'),
                ...missed.map((item) => _ReminderTile(
                      item: item,
                      repository: repository,
                      onChanged: _refresh,
                    )),
              ],
              if (future.isNotEmpty) ...[
                const _SectionTitle('即将提醒'),
                ...future.map((item) => _ReminderTile(
                      item: item,
                      repository: repository,
                      onChanged: _refresh,
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  void _refresh() => ref.read(refreshProvider.notifier).state++;
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.notifications_none, size: 64),
          SizedBox(height: 16),
          Text('未来 7 天没有提醒', textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('为任务、日程、课程、习惯或纪念日设置时间后会显示在这里。', textAlign: TextAlign.center),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.item,
    required this.repository,
    required this.onChanged,
  });

  final ReminderView item;
  final ReminderRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final local = item.triggerAt.toLocal();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(item.typeLabel.substring(0, 1))),
        title: Text(item.title),
        subtitle: Text(
          '${item.typeLabel} · ${DateFormat('MM-dd HH:mm').format(local)}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '提醒操作',
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'snooze', child: Text('20 分钟后提醒')),
            PopupMenuItem(value: 'disable', child: Text('关闭这条提醒')),
          ],
          onSelected: (value) async {
            if (value == 'snooze') {
              await repository.snooze(
                item.id,
                DateTime.now().toUtc().add(const Duration(minutes: 20)),
              );
            } else {
              await repository.setEnabled(item.id, false);
            }
            onChanged();
          },
        ),
      ),
    );
  }
}
