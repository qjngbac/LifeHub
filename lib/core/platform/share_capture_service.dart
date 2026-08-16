import 'package:flutter/services.dart';

typedef ShareCaptureHandler = void Function(String value);

abstract final class ShareCaptureService {
  static const _channel = MethodChannel('lifehub/share_capture');
  static ShareCaptureHandler? _handler;
  static bool _installed = false;

  static Future<String?> consumeInitial() async {
    _install();
    final value = await _channel.invokeMethod<String>('consumeInitialShare');
    return _normalize(value);
  }

  static void setHandler(ShareCaptureHandler? handler) {
    _handler = handler;
    _install();
  }

  static void _install() {
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedText') return;
      final value = _normalize(call.arguments?.toString());
      if (value != null) _handler?.call(value);
    });
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
