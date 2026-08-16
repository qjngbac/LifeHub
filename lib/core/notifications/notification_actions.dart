import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifehub/core/notifications/notification_service.dart';
import 'package:lifehub/core/providers.dart';

Future<void> refreshReminders(WidgetRef ref) async {
  try {
    await NotificationService.instance
        .rebuildFuture(ref.read(databaseProvider));
  } catch (_) {
    // Reminder permission or platform limitations never block local data work.
  }
}
