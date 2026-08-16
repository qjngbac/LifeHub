import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/platform/share_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/share_capture');

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('consumes initial shared text and receives foreground shares', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'consumeInitialShare') return '初始分享';
      return null;
    });
    expect(await ShareCaptureService.consumeInitial(), '初始分享');

    String? received;
    ShareCaptureService.setHandler((value) => received = value);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('sharedText', '前台分享')),
      (_) {},
    );
    expect(received, '前台分享');
    ShareCaptureService.setHandler(null);
  });
}
