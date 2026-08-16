import 'package:flutter/services.dart';

enum CourseShortcutRequest { requested, unsupported, failed }

abstract final class CourseShortcutService {
  static const _channel = MethodChannel('lifehub/course_shortcut');
  static void Function(String destination)? _destinationHandler;
  static bool _listening = false;

  static void setDestinationHandler(
    void Function(String destination)? handler,
  ) {
    _destinationHandler = handler;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  static Future<CourseShortcutRequest> requestCourseShortcut() async {
    return _request('requestCourseShortcut');
  }

  static Future<CourseShortcutRequest> requestCourseWidget() async {
    return _request('requestCourseWidget');
  }

  static Future<CourseShortcutRequest> _request(String method) async {
    try {
      final result = await _channel.invokeMethod<String>(method);
      return switch (result) {
        'requested' => CourseShortcutRequest.requested,
        'unsupported' => CourseShortcutRequest.unsupported,
        _ => CourseShortcutRequest.failed,
      };
    } on PlatformException {
      return CourseShortcutRequest.failed;
    } on MissingPluginException {
      return CourseShortcutRequest.unsupported;
    }
  }

  static Future<String?> consumeInitialDestination() async {
    try {
      return await _channel.invokeMethod<String>('consumeInitialDestination');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method == 'openDestination' && call.arguments is String) {
      _destinationHandler?.call(call.arguments as String);
    }
    return null;
  }
}
