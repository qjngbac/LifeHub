import 'package:lifehub/core/time/date_keys.dart';
import 'package:lifehub/core/time/time_zone_resolver.dart';

abstract final class MatchStatuses {
  static const scheduled = 'SCHEDULED';
  static const postponed = 'POSTPONED';
  static const cancelled = 'CANCELLED';
  static const pendingResult = 'PENDING_RESULT';
  static const finished = 'FINISHED';

  static const values = <String>{
    scheduled,
    postponed,
    cancelled,
    pendingResult,
    finished,
  };
}

abstract final class MatchSources {
  static const screenshot = 'SCREENSHOT';
  static const csv = 'CSV';
  static const ics = 'ICS';
  static const manual = 'MANUAL';
}

enum MatchIssueSeverity { warning, error }

enum MatchImportField {
  season,
  stageOrRound,
  scoreA,
  scoreB,
  scoreDetail,
  status,
  venue,
  broadcast,
  notes,
  favorite,
  sourceKey,
  sourceLabel,
}

class MatchImportIssue {
  const MatchImportIssue({
    required this.code,
    required this.message,
    this.severity = MatchIssueSeverity.error,
  });

  final String code;
  final String message;
  final MatchIssueSeverity severity;

  @override
  String toString() => '$code: $message';
}

class MatchDraft {
  const MatchDraft({
    this.sportType,
    this.competition,
    this.season,
    this.stageOrRound,
    this.participantA,
    this.participantB,
    this.matchDate,
    this.startAt,
    this.timezoneId,
    this.scoreA,
    this.scoreB,
    this.scoreDetail,
    this.status = MatchStatuses.scheduled,
    this.venue,
    this.broadcast,
    this.notes,
    this.favorite = false,
    this.sourceType = MatchSources.manual,
    this.sourceKey,
    this.sourceLabel,
    this.importFields,
  });

  final String? sportType;
  final String? competition;
  final String? season;
  final String? stageOrRound;
  final String? participantA;
  final String? participantB;
  final DateTime? matchDate;
  final DateTime? startAt;
  final String? timezoneId;
  final int? scoreA;
  final int? scoreB;
  final String? scoreDetail;
  final String status;
  final String? venue;
  final String? broadcast;
  final String? notes;
  final bool favorite;
  final String sourceType;
  final String? sourceKey;
  final String? sourceLabel;
  final Set<MatchImportField>? importFields;

  List<MatchImportIssue> validate({required DateTime now}) {
    final issues = <MatchImportIssue>[];
    void requiredText(String? value, String code, String label) {
      if (value == null || value.trim().isEmpty) {
        issues.add(MatchImportIssue(code: code, message: '$label不能为空。'));
      }
    }

    requiredText(sportType, 'MISSING_SPORT', '运动类型');
    requiredText(competition, 'MISSING_COMPETITION', '赛事');
    requiredText(participantA, 'MISSING_PARTICIPANT_A', '参赛方A');
    requiredText(participantB, 'MISSING_PARTICIPANT_B', '参赛方B');
    if (!MatchStatuses.values.contains(status)) {
      issues.add(const MatchImportIssue(
        code: 'INVALID_STATUS',
        message: '比赛状态无效。',
      ));
    }
    if (matchDate == null) {
      issues.add(const MatchImportIssue(
        code: 'MISSING_DATE',
        message: '比赛日期不能为空。',
      ));
    }

    final isHistorical = status == MatchStatuses.finished;
    final needsSchedule = status == MatchStatuses.scheduled ||
        status == MatchStatuses.pendingResult;
    if (needsSchedule) {
      if (startAt == null) {
        issues.add(const MatchImportIssue(
          code: 'MISSING_START',
          message: '未来比赛需要开始时间。',
        ));
      }
      if (timezoneId == null || timezoneId!.trim().isEmpty) {
        issues.add(const MatchImportIssue(
          code: 'MISSING_TIMEZONE',
          message: '未来比赛需要时区。',
        ));
      }
    }
    if (timezoneId != null &&
        timezoneId!.trim().isNotEmpty &&
        !TimeZoneResolver.isValid(timezoneId!)) {
      issues.add(const MatchImportIssue(
        code: 'INVALID_TIMEZONE',
        message: '比赛时区无效。',
      ));
    }
    if (scoreA == null && scoreB != null || scoreA != null && scoreB == null) {
      issues.add(const MatchImportIssue(
        code: 'INCOMPLETE_SCORE',
        message: '比分必须同时填写双方。',
      ));
    }
    if (scoreA != null && scoreA! < 0 || scoreB != null && scoreB! < 0) {
      issues.add(const MatchImportIssue(
        code: 'INVALID_SCORE',
        message: '比分不能为负数。',
      ));
    }
    if (isHistorical &&
        scoreA == null &&
        scoreB == null &&
        (scoreDetail == null || scoreDetail!.trim().isEmpty)) {
      issues.add(const MatchImportIssue(
        code: 'MISSING_RESULT',
        message: '已结束比赛需要比分或结果说明。',
      ));
    }
    if (startAt != null && timezoneId != null && timezoneId!.trim().isEmpty) {
      issues.add(const MatchImportIssue(
        code: 'MISSING_TIMEZONE',
        message: '开始时间对应的时区不能为空。',
      ));
    }
    if (matchDate != null && DateKeys.toLocalDateKey(matchDate!) < 10000101) {
      issues.add(const MatchImportIssue(
        code: 'INVALID_DATE',
        message: '比赛日期无效。',
      ));
    }
    // Keep this check deliberately informational: imported historical data may
    // legitimately be older than the current clock.
    if (startAt != null && !isHistorical && startAt!.isBefore(now)) {
      issues.add(const MatchImportIssue(
        code: 'PAST_SCHEDULED',
        message: '开始时间已经过去，请确认比赛是否需要补录结果。',
        severity: MatchIssueSeverity.warning,
      ));
    }
    return List.unmodifiable(issues);
  }

  MatchDraft copyWith({
    String? sportType,
    String? competition,
    String? season,
    String? stageOrRound,
    String? participantA,
    String? participantB,
    DateTime? matchDate,
    DateTime? startAt,
    String? timezoneId,
    int? scoreA,
    int? scoreB,
    String? scoreDetail,
    String? status,
    String? venue,
    String? broadcast,
    String? notes,
    bool? favorite,
    String? sourceType,
    String? sourceKey,
    String? sourceLabel,
    Set<MatchImportField>? importFields,
  }) {
    final supplied = importFields ?? this.importFields;
    return MatchDraft(
      sportType: sportType ?? this.sportType,
      competition: competition ?? this.competition,
      season: season ?? this.season,
      stageOrRound: stageOrRound ?? this.stageOrRound,
      participantA: participantA ?? this.participantA,
      participantB: participantB ?? this.participantB,
      matchDate: matchDate ?? this.matchDate,
      startAt: startAt ?? this.startAt,
      timezoneId: timezoneId ?? this.timezoneId,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      scoreDetail: scoreDetail ?? this.scoreDetail,
      status: status ?? this.status,
      venue: venue ?? this.venue,
      broadcast: broadcast ?? this.broadcast,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      sourceType: sourceType ?? this.sourceType,
      sourceKey: sourceKey ?? this.sourceKey,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      importFields: supplied == null
          ? null
          : {
              ...supplied,
              if (season != null) MatchImportField.season,
              if (stageOrRound != null) MatchImportField.stageOrRound,
              if (scoreA != null) MatchImportField.scoreA,
              if (scoreB != null) MatchImportField.scoreB,
              if (scoreDetail != null) MatchImportField.scoreDetail,
              if (status != null) MatchImportField.status,
              if (venue != null) MatchImportField.venue,
              if (broadcast != null) MatchImportField.broadcast,
              if (notes != null) MatchImportField.notes,
              if (favorite != null) MatchImportField.favorite,
              if (sourceKey != null) MatchImportField.sourceKey,
              if (sourceLabel != null) MatchImportField.sourceLabel,
            },
    );
  }
}

class MatchReminderTrigger {
  const MatchReminderTrigger({required this.kind, required this.triggerAt});

  final String kind;
  final DateTime triggerAt;
}

class MatchParseResult {
  const MatchParseResult({required this.drafts, required this.warnings});

  final List<MatchDraft> drafts;
  final List<String> warnings;
}

enum MatchPreviewState { ready, needsReview, invalid, duplicate }

class MatchImportPreviewRow {
  const MatchImportPreviewRow({
    required this.draft,
    required this.issues,
    this.state = MatchPreviewState.ready,
    this.possibleDuplicate = false,
    this.existingId,
    this.selected = true,
  });

  final MatchDraft draft;
  final List<MatchImportIssue> issues;
  final MatchPreviewState state;
  final bool possibleDuplicate;
  final String? existingId;
  final bool selected;

  MatchImportPreviewRow copyWith({
    MatchDraft? draft,
    List<MatchImportIssue>? issues,
    MatchPreviewState? state,
    bool? possibleDuplicate,
    String? existingId,
    bool? selected,
  }) {
    return MatchImportPreviewRow(
      draft: draft ?? this.draft,
      issues: issues ?? this.issues,
      state: state ?? this.state,
      possibleDuplicate: possibleDuplicate ?? this.possibleDuplicate,
      existingId: existingId ?? this.existingId,
      selected: selected ?? this.selected,
    );
  }
}

class MatchImportPreview {
  const MatchImportPreview({required this.rows, required this.warnings});

  final List<MatchImportPreviewRow> rows;
  final List<String> warnings;
}
