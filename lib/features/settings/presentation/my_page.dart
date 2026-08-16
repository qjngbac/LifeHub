import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/backup/encrypted_backup_codec.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/backup/background_backup_scheduler.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/settings/app_settings.dart';
import 'package:lifehub/features/data_health/presentation/data_health_page.dart';
import 'package:lifehub/features/automation/presentation/automation_page.dart';
import 'package:lifehub/features/calendar/presentation/calendar_exchange_page.dart';
import 'package:lifehub/features/reminder/presentation/reminder_center_page.dart';
import 'package:lifehub/features/onboarding/presentation/onboarding_page.dart';

class MyPage extends ConsumerWidget {
  const MyPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final preferences = ref.watch(sharedPreferencesProvider);
    final backupService = preferences == null
        ? null
        : AutomaticBackupService(ref.read(databaseProvider), preferences);
    final backupFrequency =
        backupService?.frequency ?? BackupFrequency.disabled;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('生活模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('可同时启用多个模式，只影响展示偏好，不改变历史数据。'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: LifeMode.values
                  .map((mode) => SwitchListTile(
                        title: Text('${mode.label}模式'),
                        subtitle: Text(_modeDescription(mode)),
                        value: settings.modes.contains(mode),
                        onChanged: (value) => ref
                            .read(appSettingsProvider.notifier)
                            .toggleMode(mode, value),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Text('外观与提醒', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题'),
                subtitle: Text(_themeLabel(settings.themeMode)),
                onTap: () => _chooseTheme(context, ref, settings.themeMode),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('通知权限与提醒'),
                subtitle: const Text('开启权限并重建未来 60 天提醒'),
                onTap: () => _enableNotifications(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('提醒中心'),
                subtitle: const Text('查看未来提醒、错过提醒和关闭状态'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReminderCenterPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('使用引导'),
                subtitle: const Text('重新查看首页、日程、数据页、提醒和备份说明'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnboardingPage(
                      onFinished: () async {
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('本地数据', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('导出 JSON 备份'),
                subtitle: const Text('使用系统文件选择器保存到手机可见位置'),
                onTap: () => _export(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: const Text('导出密码加密备份'),
                subtitle: const Text('保护心情、关系空间和附件；密码不会保存，丢失后无法恢复'),
                onTap: () => _exportEncrypted(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('导入 JSON 备份'),
                subtitle: const Text('导入前会先自动保存当前数据安全快照'),
                onTap: () => _importPicked(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('恢复最近备份'),
                subtitle: const Text('恢复前会要求确认，导入失败不会覆盖现有数据'),
                onTap: () => _restore(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: const Text('数据健康检查'),
                subtitle: const Text('检查孤立关联、无效时间和失效提醒'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DataHealthPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('日历导入导出'),
                subtitle: const Text('使用 ICS 文件交换日程，导入前先预览'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CalendarExchangePage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('本地自动化'),
                subtitle: const Text('创建可预览、可关闭并有执行记录的规则'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AutomationPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('自动本地备份'),
                subtitle: Text(backupService == null
                    ? '未配置'
                    : '${_backupFrequencyLabel(backupFrequency)} · Android 后台任务 · 保留 ${backupService.retention} 份'
                        '${backupService.lastResult == null ? '' : ' · ${backupService.lastResult}'}'),
                onTap: () => _chooseBackupFrequency(context, ref),
              ),
              const ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('云同步'),
                subtitle: Text('未启用 · 当前版本完全离线使用'),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const Center(child: Text('LifeHub V1.9.1 · Android · 本地优先')),
        ],
      ),
    );
  }

  Future<void> _chooseTheme(
      BuildContext context, WidgetRef ref, ThemeMode current) async {
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择主题'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ThemeMode.values
                  .map((mode) => RadioListTile<ThemeMode>(
                        value: mode,
                        title: Text(_themeLabel(mode)),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (mode != null) {
      await ref.read(appSettingsProvider.notifier).setTheme(mode);
    }
  }

  Future<void> _enableNotifications(BuildContext context, WidgetRef ref) async {
    try {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (context.mounted) _message(context, '通知权限未开启，其他功能仍可正常使用');
        return;
      }
      final count = await NotificationService.instance
          .rebuildFuture(ref.read(databaseProvider));
      if (context.mounted) _message(context, '已重建 $count 条未来提醒');
    } catch (_) {
      if (context.mounted) _message(context, '提醒设置失败，请检查系统通知权限');
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final includeFiles = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('选择备份内容'),
        content: const Text('完整备份包含附件文件，体积更大；纯数据备份保留附件记录，但不复制附件文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('仅数据'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('完整备份'),
          ),
        ],
      ),
    );
    if (includeFiles == null) return;
    try {
      final saved = await BackupService(ref.read(databaseProvider))
          .exportWithPicker(includeAttachmentFiles: includeFiles);
      if (context.mounted && saved) _message(context, '备份已保存');
    } catch (_) {
      if (context.mounted) _message(context, '备份导出失败，请检查存储空间');
    }
  }

  Future<void> _exportEncrypted(BuildContext context, WidgetRef ref) async {
    final password = await _passwordDialog(context, confirm: true);
    if (password == null || !context.mounted) return;
    final includeFiles = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('选择加密备份内容'),
        content: const Text('完整备份会把附件内容一并加密；仅数据备份不复制附件文件。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('仅数据')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完整备份')),
        ],
      ),
    );
    if (includeFiles == null) return;
    try {
      final saved = await BackupService(ref.read(databaseProvider))
          .exportEncryptedWithPicker(
        password,
        includeAttachmentFiles: includeFiles,
      );
      if (context.mounted && saved) _message(context, '加密备份已保存');
    } catch (_) {
      if (context.mounted) _message(context, '加密备份导出失败');
    }
  }

  Future<void> _importPicked(BuildContext context, WidgetRef ref) async {
    final service = BackupService(ref.read(databaseProvider));
    try {
      var source = await service.pickBackupText();
      if (source == null || !context.mounted) return;
      if (EncryptedBackupCodec.looksEncrypted(source)) {
        final password = await _passwordDialog(context);
        if (password == null) return;
        source = await EncryptedBackupCodec().decrypt(source, password);
      }
      if (!context.mounted) return;
      final inspection = service.inspectJson(source);
      final total = inspection.recordCounts.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );
      final mode = await showDialog<ImportMode>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('导入备份'),
          content: Text(
            '数据库版本 ${inspection.schemaVersion}，共 $total 条记录。\n\n合并会保留本机独有数据；替换会先创建安全快照。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, ImportMode.merge),
                child: const Text('合并导入')),
            FilledButton(
                onPressed: () => Navigator.pop(context, ImportMode.replace),
                child: const Text('替换导入')),
          ],
        ),
      );
      if (mode == null) return;
      if (mode == ImportMode.replace) await service.exportToFile();
      await service.importJson(source, mode: mode);
      ref.read(refreshProvider.notifier).state++;
      await NotificationService.instance
          .rebuildFuture(ref.read(databaseProvider));
      if (context.mounted) {
        _message(
          context,
          mode == ImportMode.merge ? '备份合并完成' : '备份替换完成',
        );
      }
    } catch (_) {
      if (context.mounted) _message(context, '备份无效，当前数据未被修改');
    }
  }

  Future<String?> _passwordDialog(
    BuildContext context, {
    bool confirm = false,
  }) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(confirm ? '设置备份密码' : '输入备份密码'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('密码不会保存或上传。请自行妥善保管。'),
              TextField(
                controller: password,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码（至少 8 个字符）'),
              ),
              if (confirm)
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再次输入密码'),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (password.text.length < 8) {
                  setDialogState(() => error = '密码至少需要 8 个字符');
                } else if (confirm && password.text != confirmation.text) {
                  setDialogState(() => error = '两次密码不一致');
                } else {
                  Navigator.pop(context, password.text);
                }
              },
              child: Text(confirm ? '继续导出' : '解密'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    confirmation.dispose();
    return result;
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final service = BackupService(ref.read(databaseProvider));
    late final List<File> files;
    try {
      files = await service.backupFiles();
    } catch (_) {
      if (context.mounted) _message(context, '无法读取备份目录');
      return;
    }
    if (!context.mounted) return;
    if (files.isEmpty) {
      _message(context, '还没有可恢复的备份');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复最近备份？'),
        content: Text(
            '将使用 ${files.first.path.split(Platform.pathSeparator).last} 替换当前本地数据。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认恢复')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.importFile(files.first);
      ref.read(refreshProvider.notifier).state++;
      await NotificationService.instance
          .rebuildFuture(ref.read(databaseProvider));
      if (context.mounted) _message(context, '备份恢复完成');
    } catch (_) {
      if (context.mounted) _message(context, '备份无效，当前数据未被修改');
    }
  }

  Future<void> _chooseBackupFrequency(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final preferences = ref.read(sharedPreferencesProvider);
    if (preferences == null) return;
    final service =
        AutomaticBackupService(ref.read(databaseProvider), preferences);
    var frequency = service.frequency;
    var retention = service.retention;
    final selected = await showDialog<(BackupFrequency, int)>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('自动本地备份'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioGroup<BackupFrequency>(
                groupValue: frequency,
                onChanged: (choice) {
                  if (choice != null) setLocal(() => frequency = choice);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: BackupFrequency.values
                      .map((value) => RadioListTile<BackupFrequency>(
                            value: value,
                            title: Text(_backupFrequencyLabel(value)),
                          ))
                      .toList(),
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: retention,
                decoration: const InputDecoration(labelText: '保留备份数'),
                items: const [3, 5, 10, 15, 20, 30]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value 份'),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setLocal(() => retention = value ?? retention),
              ),
              const SizedBox(height: 8),
              const Text('由 Android 后台调度，具体执行时间可能因省电策略延后。'),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (frequency, retention)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await service.setFrequency(selected.$1);
    await service.setRetention(selected.$2);
    await BackgroundBackupScheduler.sync(selected.$1);
    if (context.mounted) _message(context, '自动备份设置已保存');
  }

  void _message(BuildContext context, String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
}

String _themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
String _modeDescription(LifeMode mode) => switch (mode) {
      LifeMode.student => '突出课程与学习任务',
      LifeMode.work => '突出项目与会议',
      LifeMode.daily => '突出生活任务与习惯',
      LifeMode.outdoor => '突出行程与装备清单',
    };

String _backupFrequencyLabel(BackupFrequency value) => switch (value) {
      BackupFrequency.disabled => '关闭',
      BackupFrequency.daily => '每天（应用启动时检查）',
      BackupFrequency.weekly => '每周（应用启动时检查）',
    };
