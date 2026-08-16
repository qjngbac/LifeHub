import 'package:lifehub/core/backup/backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackupFrequency { disabled, daily, weekly }

abstract final class AutomaticBackupPolicy {
  static bool isDue({
    required BackupFrequency frequency,
    required DateTime? lastRun,
    required DateTime now,
  }) {
    if (frequency == BackupFrequency.disabled) return false;
    if (lastRun == null) return true;
    final interval = frequency == BackupFrequency.daily
        ? const Duration(days: 1)
        : const Duration(days: 7);
    return !lastRun.add(interval).isAfter(now);
  }
}

class AutomaticBackupService {
  AutomaticBackupService(this._database, this._preferences);
  final AppDatabase _database;
  final SharedPreferences _preferences;

  static const frequencyKey = 'backup.auto.frequency';
  static const lastRunKey = 'backup.auto.lastRun';
  static const lastResultKey = 'backup.auto.lastResult';
  static const failureReasonKey = 'backup.auto.failureReason';
  static const retentionKey = 'backup.auto.retention';

  BackupFrequency get frequency {
    final stored = _preferences.getString(frequencyKey);
    return BackupFrequency.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => BackupFrequency.disabled,
    );
  }

  Future<void> setFrequency(BackupFrequency value) =>
      _preferences.setString(frequencyKey, value.name);

  int get retention => (_preferences.getInt(retentionKey) ?? 10).clamp(1, 30);
  String? get lastResult => _preferences.getString(lastResultKey);
  String? get failureReason => _preferences.getString(failureReasonKey);

  Future<void> setRetention(int value) =>
      _preferences.setInt(retentionKey, value.clamp(1, 30));

  Future<bool> runIfDue({DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    final lastText = _preferences.getString(lastRunKey);
    final last = lastText == null ? null : DateTime.tryParse(lastText);
    if (!AutomaticBackupPolicy.isDue(
      frequency: frequency,
      lastRun: last,
      now: timestamp,
    )) {
      return false;
    }
    return runNow(now: timestamp);
  }

  Future<bool> runNow({DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    try {
      final backup = BackupService(_database);
      await backup.exportToFile();
      final files = await backup.backupFiles();
      for (final file in files.skip(retention)) {
        await file.delete();
      }
      await _preferences.setString(lastRunKey, timestamp.toIso8601String());
      await _preferences.setString(lastResultKey, 'SUCCESS');
      await _preferences.remove(failureReasonKey);
      return true;
    } catch (error) {
      await _preferences.setString(lastResultKey, 'FAILED');
      await _preferences.setString(failureReasonKey, '$error');
      return false;
    }
  }
}
