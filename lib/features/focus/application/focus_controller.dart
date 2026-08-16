import 'package:lifehub/core/database/app_database.dart';
import 'package:lifehub/features/focus/data/focus_repository.dart';

class FocusController {
  FocusController(this._repository, {this.onCompleted});

  final FocusRepository _repository;
  final Future<void> Function(FocusSessionEntry session)? onCompleted;
  FocusSessionEntry? session;
  bool _completionReported = false;

  Future<FocusSessionEntry?> load() async {
    session = await _repository.active();
    _completionReported = false;
    return session;
  }

  Future<bool> tick(DateTime now) async {
    final current = session;
    if (current == null || current.status != FocusStatus.running) return false;
    final finished = await _repository.finishIfDue(current.id, now: now);
    if (finished == null || finished.status != FocusStatus.finished) {
      return false;
    }
    session = null;
    if (_completionReported) return false;
    _completionReported = true;
    await onCompleted?.call(finished);
    return true;
  }

  Future<void> reload() async {
    session = await _repository.active();
  }
}
