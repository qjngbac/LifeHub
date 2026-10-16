import 'package:flutter/services.dart';

class WhiteNoiseItem {
  const WhiteNoiseItem({
    required this.id,
    required this.name,
    required this.assetPath,
  });

  final String id;
  final String name;
  final String assetPath;
}

class WhiteNoiseService {
  WhiteNoiseService._();
  static final WhiteNoiseService instance = WhiteNoiseService._();

  static const MethodChannel _channel = MethodChannel('lifehub/white_noise');

  static const List<WhiteNoiseItem> available = [
    WhiteNoiseItem(id: 'rain', name: '细雨', assetPath: 'assets/audio/rain.wav'),
    WhiteNoiseItem(
        id: 'campfire', name: '篝火', assetPath: 'assets/audio/campfire.wav'),
    WhiteNoiseItem(
        id: 'waves', name: '海浪', assetPath: 'assets/audio/waves.wav'),
    WhiteNoiseItem(
        id: 'forest', name: '森林', assetPath: 'assets/audio/forest.wav'),
  ];

  String? currentSoundId;
  bool isPlaying = false;
  double volume = 0.5;
  String? lastError;

  Future<void> play(String soundId, {double? newVolume}) async {
    final item = available.where((item) => item.id == soundId).firstOrNull;
    if (item == null) {
      await stop();
      return;
    }
    final nextVolume = (newVolume ?? volume).clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod('play', {
        'asset': item.assetPath,
        'volume': nextVolume,
      });
      currentSoundId = soundId;
      isPlaying = true;
      volume = nextVolume;
      lastError = null;
    } catch (_) {
      currentSoundId = null;
      isPlaying = false;
      lastError = '白噪音播放失败，请重试';
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
      isPlaying = false;
      lastError = null;
    } catch (_) {
      lastError = '白噪音暂停失败，请重试';
    }
  }

  Future<void> resume() async {
    if (currentSoundId == null) return;
    try {
      await _channel.invokeMethod('resume');
      isPlaying = true;
      lastError = null;
    } catch (_) {
      lastError = '白噪音恢复失败，请重试';
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      lastError = null;
    } catch (_) {
      lastError = '白噪音停止失败，请重试';
    }
    currentSoundId = null;
    isPlaying = false;
  }

  Future<void> setVolume(double newVolume) async {
    final nextVolume = newVolume.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod('setVolume', {'volume': nextVolume});
      volume = nextVolume;
      lastError = null;
    } catch (_) {
      lastError = '白噪音音量调整失败，请重试';
    }
  }
}
