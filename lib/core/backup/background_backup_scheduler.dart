import 'package:flutter/widgets.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/features/automation/application/automation_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

abstract final class BackgroundBackupScheduler {
  static const uniqueName = 'lifehub-periodic-local-backup';
  static const taskName = 'lifehub.localBackup';

  static Future<void> initialize() =>
      Workmanager().initialize(lifeHubBackgroundDispatcher);

  static Future<void> sync(BackupFrequency frequency) async {
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'lifehub-maintenance',
    );
  }
}

@pragma('vm:entry-point')
void lifeHubBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != BackgroundBackupScheduler.taskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    AppDatabase? database;
    try {
      final preferences = await SharedPreferences.getInstance();
      database = AppDatabase();
      final now = DateTime.now();
      await AutomationEngine(database).runDue(now);
      await WidgetSnapshotService(database).refresh(
        now: now,
        preferences: preferences,
        notifyNative: false,
      );
      await AutomaticBackupService(database, preferences).runIfDue(now: now);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Background backup failed: $error\n$stackTrace');
      return false;
    } finally {
      await database?.close();
    }
  });
}
