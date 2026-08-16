import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/platform/course_shortcut_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/course_shortcut');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    CourseShortcutService.setDestinationHandler(null);
  });

  test('requests the native course shortcut and maps its result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCourseShortcut');
      return 'requested';
    });

    expect(
      await CourseShortcutService.requestCourseShortcut(),
      CourseShortcutRequest.requested,
    );
  });

  test('requests the dynamic course widget and maps unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestCourseWidget');
      return 'unsupported';
    });

    expect(
      await CourseShortcutService.requestCourseWidget(),
      CourseShortcutRequest.unsupported,
    );
  });

  test('consumes initial destination and receives later native navigation',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumeInitialDestination') return 'courses';
      return null;
    });
    String? received;
    CourseShortcutService.setDestinationHandler((value) => received = value);

    expect(
      await CourseShortcutService.consumeInitialDestination(),
      'courses',
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'lifehub/course_shortcut',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openDestination', 'courses'),
      ),
      (_) {},
    );
    expect(received, 'courses');
  });
}
