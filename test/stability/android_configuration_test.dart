import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest registers notification restart and action receivers',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('ActionBroadcastReceiver'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(manifest, contains('android.intent.action.TIMEZONE_CHANGED'));
    expect(manifest, contains('.CourseWidgetProvider'));
    expect(manifest, contains('.TodayWidgetProvider'));
  });

  test('widgets discard elapsed entries without opening the app', () {
    for (final name in ['CourseWidgetProvider.kt', 'TodayWidgetProvider.kt']) {
      final source = File(
        'android/app/src/main/kotlin/com/lifehub/app/lifehub/$name',
      ).readAsStringSync();
      expect(source, contains('System.currentTimeMillis()'));
      expect(source, contains('optLong("endAt") > now'));
      expect(
        source,
        contains(
            name == 'CourseWidgetProvider.kt' ? 'sortedBy' : 'minByOrNull'),
      );
    }
  });

  test('course widget renders at most two remaining courses for today', () {
    final source = File(
      'android/app/src/main/kotlin/com/lifehub/app/lifehub/CourseWidgetProvider.kt',
    ).readAsStringSync();
    final layout = File(
      'android/app/src/main/res/layout/widget_course.xml',
    ).readAsStringSync();
    expect(source, contains('.take(2)'));
    expect(source, contains('yyyyMMdd'));
    expect(layout, contains('widget_course_second_title'));
    expect(layout, contains('widget_course_second_detail'));
  });

  test('widget providers request a periodic launcher refresh', () {
    for (final name in ['course_widget_info.xml', 'today_widget_info.xml']) {
      final source =
          File('android/app/src/main/res/xml/$name').readAsStringSync();
      expect(source, contains('android:updatePeriodMillis="1800000"'));
    }
  });

  test('background maintenance rebuilds local widget data', () {
    final source = File('lib/core/backup/background_backup_scheduler.dart')
        .readAsStringSync();
    expect(source, contains("@pragma('vm:entry-point')"));
    expect(source, contains('WidgetSnapshotService(database).refresh'));
    expect(source, contains('AutomationEngine(database).runDue'));
    expect(source, contains('AutomaticBackupService(database, preferences)'));
  });

  test('automation widget refresh and backup use independent background jobs',
      () {
    final source = File('lib/core/backup/background_backup_scheduler.dart')
        .readAsStringSync();
    expect(source, contains('lifehub.periodicAutomation'));
    expect(source, contains('lifehub.periodicWidgetRefresh'));
    expect(source, contains('lifehub.periodicLocalBackup'));
    expect(source, contains('Duration(minutes: 30)'));
    expect(source, contains('cancelByUniqueName(legacyUniqueName)'));
  });

  test('native widgets load the background snapshot file before rendering', () {
    final store = File(
      'android/app/src/main/kotlin/com/lifehub/app/lifehub/WidgetSnapshotStore.kt',
    );
    expect(store.existsSync(), isTrue);
    expect(store.readAsStringSync(), contains('lifehub_widget_snapshot.json'));
    for (final name in ['CourseWidgetProvider.kt', 'TodayWidgetProvider.kt']) {
      final source = File(
        'android/app/src/main/kotlin/com/lifehub/app/lifehub/$name',
      ).readAsStringSync();
      expect(
          source, contains('WidgetSnapshotStore.refreshPreferences(context)'));
    }
  });

  test('destructive backup drill rejects physical devices before pm clear', () {
    final source =
        File('tool/stability/run_backup_restore_drill.ps1').readAsStringSync();
    final guard = source.indexOf(r"if ($qemu -ne '1'");
    final clear = source.indexOf('shell pm clear');
    expect(guard, greaterThanOrEqualTo(0));
    expect(clear, greaterThan(guard));
    expect(source, contains(r"$Serial.StartsWith('emulator-')"));
  });

  test('debug build installs beside an existing release build', () {
    final source = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final debugStrings = File('android/app/src/debug/res/values/strings.xml');
    expect(source, contains('debug {'));
    expect(source, contains('applicationIdSuffix = ".debug"'));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(debugStrings.existsSync(), isTrue);
    expect(debugStrings.readAsStringSync(), contains('LifeHub Debug'));
  });

  test('release builds fail closed when signing credentials are missing', () {
    final source = File('android/app/build.gradle.kts').readAsStringSync();
    expect(source, contains('releaseBuildRequested'));
    expect(source, contains('throw GradleException'));
    expect(source, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('Android launcher keeps full artwork inside the adaptive icon mask', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    );
    final artwork = File(
      'android/app/src/main/res/drawable-nodpi/ic_launcher_artwork.png',
    );
    final monochrome = File(
      'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
    );
    expect(adaptive.existsSync(), isTrue);
    final source = adaptive.readAsStringSync();
    expect(source, contains('@drawable/ic_launcher_artwork'));
    expect(source, contains('@android:color/transparent'));
    expect(source, contains('<monochrome'));
    expect(artwork.existsSync(), isTrue);
    expect(artwork.lengthSync(), greaterThan(0));
    expect(monochrome.existsSync(), isTrue);
  });
}
