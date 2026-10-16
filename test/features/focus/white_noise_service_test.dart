import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/focus/application/white_noise_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lifehub/white_noise');
  final service = WhiteNoiseService.instance;

  tearDown(() async {
    await service.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('failed replacement clears stale playing state and allows retry',
      () async {
    var rejectPlay = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'play' && rejectPlay) {
        throw PlatformException(code: 'AUDIO_ERROR', message: 'prepare failed');
      }
      return true;
    });
    await service.play('rain');
    expect(service.isPlaying, isTrue);
    rejectPlay = true;
    await service.play('waves');

    expect(service.currentSoundId, isNull);
    expect(service.isPlaying, isFalse);
    rejectPlay = false;
    await service.play('waves');
    expect(service.currentSoundId, 'waves');
    expect(service.isPlaying, isTrue);
  });
}
