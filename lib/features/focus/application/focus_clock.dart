import 'package:lifehub/core/database/app_database.dart';

abstract final class FocusClock {
  static Duration elapsed(FocusSessionEntry session, DateTime now) {
    final start =
        DateTime.fromMillisecondsSinceEpoch(session.startedAt, isUtc: true);
    final effectiveEnd = session.endedAt == null
        ? now.toUtc()
        : DateTime.fromMillisecondsSinceEpoch(session.endedAt!, isUtc: true);
    var paused = Duration(milliseconds: session.pausedMillis);
    if (session.pausedAt != null && session.endedAt == null) {
      final pauseStart =
          DateTime.fromMillisecondsSinceEpoch(session.pausedAt!, isUtc: true);
      paused += effectiveEnd.difference(pauseStart);
    }
    final result = effectiveEnd.difference(start) - paused;
    return result.isNegative ? Duration.zero : result;
  }
}
