import 'match_models.dart';

abstract final class MatchRules {
  static String? normalizeSourceKey(MatchDraft draft) {
    if (draft.importFields != null &&
        !draft.importFields!.contains(MatchImportField.sourceKey)) {
      return null;
    }
    final source = _normalize(draft.sourceKey);
    return source.isEmpty ? null : source;
  }

  static String normalizeMatchKey(MatchDraft draft) {
    final date = draft.startAt != null || draft.matchDate == null
        ? ''
        : '${draft.matchDate!.year.toString().padLeft(4, '0')}'
            '${draft.matchDate!.month.toString().padLeft(2, '0')}'
            '${draft.matchDate!.day.toString().padLeft(2, '0')}';
    final minute = draft.startAt == null
        ? ''
        : '${draft.startAt!.toUtc().millisecondsSinceEpoch ~/ 60000}';
    return [
      _normalize(draft.sportType),
      _normalize(draft.competition),
      _normalize(draft.participantA),
      _normalize(draft.participantB),
      date,
      minute,
    ].join('|');
  }

  static String normalizeKey(MatchDraft draft) {
    final source = normalizeSourceKey(draft);
    return source == null ? normalizeMatchKey(draft) : 'source:$source';
  }

  static bool areDuplicates(MatchDraft first, MatchDraft second) {
    final source = normalizeSourceKey(first);
    if (source != null && source == normalizeSourceKey(second)) return true;
    if (normalizeMatchKey(first) != normalizeMatchKey(second)) return false;
    for (final pair in [
      (first.season, second.season),
      (first.stageOrRound, second.stageOrRound),
    ]) {
      final left = _normalize(pair.$1);
      final right = _normalize(pair.$2);
      if (left.isNotEmpty && right.isNotEmpty && left != right) return false;
    }
    return true;
  }

  static List<MatchReminderTrigger> computeReminderTriggers(
    DateTime startAt,
    DateTime now,
  ) {
    final start = startAt.toUtc();
    final current = now.toUtc();
    final windows = <MatchReminderTrigger>[
      MatchReminderTrigger(
        kind: 'BEFORE_8H',
        triggerAt: start.subtract(const Duration(hours: 8)),
      ),
      MatchReminderTrigger(
        kind: 'BEFORE_1H',
        triggerAt: start.subtract(const Duration(hours: 1)),
      ),
    ];
    return List.unmodifiable(
      windows.where((item) => item.triggerAt.isAfter(current)),
    );
  }

  static String transitionToPendingResult({
    required String status,
    required DateTime? startAt,
    required DateTime now,
  }) {
    if (status == MatchStatuses.scheduled &&
        startAt != null &&
        !startAt.isAfter(now)) {
      return MatchStatuses.pendingResult;
    }
    return status;
  }

  static String _normalize(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
