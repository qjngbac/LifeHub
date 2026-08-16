import 'package:flutter/services.dart';

enum AttachmentOpenResult { opened, missing, noHandler, failed }

abstract final class AttachmentOpenService {
  static const _channel = MethodChannel('lifehub/attachments');

  static Future<AttachmentOpenResult> open(String path) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'openFile',
        {'path': path},
      );
      return switch (result) {
        'opened' => AttachmentOpenResult.opened,
        'missing' => AttachmentOpenResult.missing,
        'no_handler' => AttachmentOpenResult.noHandler,
        _ => AttachmentOpenResult.failed,
      };
    } on MissingPluginException {
      return AttachmentOpenResult.noHandler;
    } on PlatformException {
      return AttachmentOpenResult.failed;
    }
  }
}
