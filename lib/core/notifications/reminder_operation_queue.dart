import 'dart:async';

class _ReminderOperation {
  bool active = true;
}

/// Serializes notification rebuilds and user actions in each Flutter isolate.
abstract final class ReminderOperationQueue {
  static final _zoneKey = Object();
  static Future<void> _tail = Future.value();

  static Future<T> run<T>(Future<T> Function() operation) {
    final current = Zone.current[_zoneKey];
    if (current is _ReminderOperation && current.active) return operation();
    return enqueue(operation);
  }

  /// External native callbacks may inherit a registration Zone, so always queue.
  static Future<T> enqueue<T>(Future<T> Function() operation) {
    final previous = _tail;
    final completed = Completer<void>();
    final token = _ReminderOperation();
    _tail = completed.future;
    return runZoned(() async {
      await previous;
      try {
        return await operation();
      } finally {
        token.active = false;
        completed.complete();
      }
    }, zoneValues: {_zoneKey: token});
  }
}
