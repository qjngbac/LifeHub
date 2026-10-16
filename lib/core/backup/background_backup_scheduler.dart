import 'package:flutter/widgets.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/platform/widget_snapshot_service.dart';
import 'package:lifehub/features/automation/application/automation_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

abstract final class BackgroundBackupScheduler {
  static const legacyUniqueName = 'lifehub-periodic-local-backup';
  static const automationUniqueName = 'lifehub-periodic-automation';
  static const widgetUniqueName = 'lifehub-periodic-widget-refresh';
  static const backupUniqueName = 'lifehub-periodic-local-backup-v2';
  static const automationTaskName = 'lifehub.periodicAutomation';
  static const widgetTaskName = 'lifehub.periodicWidgetRefresh';
  static const backupTaskName = 'lifehub.periodicLocalBackup';
  static const reminderUniqueName = 'lifehub-periodic-reminder-refresh';
  static const reminderTaskName = 'lifehub.periodicReminderRefresh';

  static Future<void> initialize() =>
      Workmanager().initialize(lifeHubBackgroundDispatcher);

  static Future<void> sync(BackupFrequency frequency) async {
    final workmanager = Workmanager();
    await workmanager.cancelByUniqueName(legacyUniqueName);
    await workmanager.registerPeriodicTask(
      automationUniqueName,
      automationTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'lifehub-automation',
    );
    await workmanager.registerPeriodicTask(
      widgetUniqueName,
      widgetTaskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'lifehub-widget-refresh',
    );
    await workmanager.registerPeriodicTask(
      reminderUniqueName,
      reminderTaskName,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'lifehub-reminder-refresh',
    );
    if (frequency == BackupFrequency.disabled) {
      await workmanager.cancelByUniqueName(backupUniqueName);
      return;
    }
    await workmanager.registerPeriodicTask(
      backupUniqueName,
      backupTaskName,
      frequency: frequency == BackupFrequency.daily
          ? const Duration(days: 1)
          : const Duration(days: 7),
      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'lifehub-local-backup',
    );
  }
}

@pragma('vm:entry-point')
void lifeHubBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (!{
      BackgroundBackupScheduler.automationTaskName,
      BackgroundBackupScheduler.widgetTaskName,
      BackgroundBackupScheduler.backupTaskName,
      BackgroundBackupScheduler.reminderTaskName,
    }.contains(taskName)) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    AppDatabase? database;
    try {
      database = AppDatabase();
      final now = DateTime.now();
      switch (taskName) {
        case BackgroundBackupScheduler.automationTaskName:
          await AutomationEngine(database).runDue(now);
        case BackgroundBackupScheduler.widgetTaskName:
          final preferences = await SharedPreferences.getInstance();
          await WidgetSnapshotService(database).refresh(
            now: now,
            preferences: preferences,
            notifyNative: false,
          );
        case BackgroundBackupScheduler.backupTaskName:
          final preferences = await SharedPreferences.getInstance();
          await AutomaticBackupService(database, preferences)
              .runIfDue(now: now);
        case BackgroundBackupScheduler.reminderTaskName:
          await NotificationService.instance.rebuildFuture(database);
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint('Background task $taskName failed: $error\n$stackTrace');
      return false;
    } finally {
      await database?.close();
    }
  });
}
