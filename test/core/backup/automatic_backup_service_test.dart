import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:lifehub/core/backup/automatic_backup_service.dart';
import 'package:lifehub/core/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('daily and weekly policies become due only after their interval', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    expect(
      AutomaticBackupPolicy.isDue(
        frequency: BackupFrequency.daily,
        lastRun: now.subtract(const Duration(hours: 25)),
        now: now,
      ),
      isTrue,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        frequency: BackupFrequency.weekly,
        lastRun: now.subtract(const Duration(days: 6)),
        now: now,
      ),
      isFalse,
    );
    expect(
      AutomaticBackupPolicy.isDue(
        frequency: BackupFrequency.disabled,
        lastRun: null,
        now: now,
      ),
      isFalse,
    );
  });

  test('retention and result settings have bounded offline defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final service = AutomaticBackupService(database, preferences);

    expect(service.retention, 10);
    await service.setRetention(99);
    expect(service.retention, 30);
    expect(service.lastResult, isNull);
    expect(service.failureReason, isNull);
  });
}
