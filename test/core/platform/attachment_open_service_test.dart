import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/platform/attachment_open_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/attachments');

  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('maps native file open results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openFile');
      expect((call.arguments as Map)['path'], 'D:/private/report.pdf');
      return 'opened';
    });

    expect(
      await AttachmentOpenService.open('D:/private/report.pdf'),
      AttachmentOpenResult.opened,
    );
  });
}
