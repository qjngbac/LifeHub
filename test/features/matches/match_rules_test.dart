import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/matches/domain/match_models.dart';
import 'package:lifehub/features/matches/domain/match_rules.dart';

void main() {
  test('future draft requires date, start time and timezone', () {
    final draft = MatchDraft(
      sportType: '足球',
      competition: '英超',
      participantA: '阿森纳',
      participantB: '切尔西',
      matchDate: DateTime(2026, 9, 7),
      startAt: null,
      timezoneId: null,
      status: MatchStatuses.scheduled,
      sourceType: MatchSources.manual,
    );
    expect(
      draft.validate(now: DateTime(2026, 9, 1)),
      contains(predicate<MatchImportIssue>((i) => i.code == 'MISSING_START')),
    );
  });

  test('scheduled match at start time becomes pending result', () {
    expect(
      MatchRules.transitionToPendingResult(
        status: MatchStatuses.scheduled,
        startAt: DateTime(2026, 9, 7, 20),
        now: DateTime(2026, 9, 7, 20),
      ),
      MatchStatuses.pendingResult,
    );
  });

  test('more than eight hours schedules both fixed reminder windows', () {
    final now = DateTime.utc(2026, 9, 7, 10);
    final triggers = MatchRules.computeReminderTriggers(
      DateTime.utc(2026, 9, 7, 20),
      now,
    );

    expect(triggers.map((item) => item.kind), ['BEFORE_8H', 'BEFORE_1H']);
    expect(triggers.map((item) => item.triggerAt), [
      DateTime.utc(2026, 9, 7, 12),
      DateTime.utc(2026, 9, 7, 19),
    ]);
  });

  test('one to eight hours schedules only the one-hour reminder', () {
    final triggers = MatchRules.computeReminderTriggers(
      DateTime.utc(2026, 9, 7, 20),
      DateTime.utc(2026, 9, 7, 15),
    );

    expect(triggers.map((item) => item.kind), ['BEFORE_1H']);
    expect(triggers.single.triggerAt, DateTime.utc(2026, 9, 7, 19));
  });

  test('less than one hour schedules no missed reminders', () {
    final triggers = MatchRules.computeReminderTriggers(
      DateTime.utc(2026, 9, 7, 20),
      DateTime.utc(2026, 9, 7, 19, 30),
    );

    expect(triggers, isEmpty);
  });

  test('source key takes precedence in duplicate key', () {
    final key = MatchRules.normalizeKey(const MatchDraft(sourceKey: '  ABC  '));
    expect(key, 'source:abc');
  });
}
