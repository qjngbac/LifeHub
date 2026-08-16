import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/app/app.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/backup/background_backup_scheduler.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/features/automation/application/automation_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  try {
    await BackgroundBackupScheduler.initialize();
  } catch (error) {
    debugPrint('Background backup initialization skipped: $error');
  }
  final database = AppDatabase();
  try {
    await database.customSelect('SELECT 1').get();
  } catch (error) {
    await database.close();
    runApp(_StartupFailureApp(error: error));
    return;
  }
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      databaseProvider.overrideWithValue(database),
    ],
  );
  NotificationService.instance.configureActions(database);
  runApp(UncontrolledProviderScope(
    container: container,
    child: const LifeHubApp(),
  ));
  unawaited(_refreshNotifications(container));
  unawaited(_runLocalMaintenance(database, preferences));
  unawaited(_syncBackgroundBackup(database, preferences));
}

Future<void> _syncBackgroundBackup(
  AppDatabase database,
  SharedPreferences preferences,
) async {
  try {
    final frequency = AutomaticBackupService(database, preferences).frequency;
    await BackgroundBackupScheduler.sync(frequency);
  } catch (error) {
    debugPrint('Background backup scheduling skipped: $error');
  }
}

Future<void> _runLocalMaintenance(
  AppDatabase database,
  SharedPreferences preferences,
) async {
  try {
    await AutomationEngine(database).runDue(DateTime.now());
    await AutomaticBackupService(database, preferences).runIfDue();
    await WidgetSnapshotService(database).refresh(preferences: preferences);
  } catch (error) {
    debugPrint('Local maintenance skipped: $error');
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('LifeHub 启动失败')),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storage_outlined, size: 64),
                const SizedBox(height: 16),
                const Text(
                  '本地数据库无法打开。请不要卸载应用，先重启手机后再试。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$error',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
}

Future<void> _refreshNotifications(ProviderContainer container) async {
  try {
    await NotificationService.instance
        .rebuildFuture(container.read(databaseProvider));
  } catch (error) {
    debugPrint('Notification refresh skipped: $error');
  }
}
