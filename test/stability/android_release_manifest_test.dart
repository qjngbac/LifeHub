import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release manifest grants internet access for online weather', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'INTERNET must be in main, not only debug, manifest.',
    );
  });

  test('course widget has a named 4x2 preview and pin callback', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final info = File('android/app/src/main/res/xml/course_widget_info.xml')
        .readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lifehub/app/lifehub/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('@string/course_widget_label'));
    expect(manifest, contains('.CourseWidgetPinReceiver'));
    expect(info, contains('android:targetCellWidth="4"'));
    expect(info, contains('android:targetCellHeight="2"'));
    expect(activity, contains('AppWidgetManager.EXTRA_APPWIDGET_PREVIEW'));
    expect(activity, contains('CourseWidgetPinReceiver::class.java'));
  });
}
