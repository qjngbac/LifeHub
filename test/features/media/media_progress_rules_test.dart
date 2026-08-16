import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/features/media/domain/media_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 20);

  test('episode progress starts watching and reports the next episode', () {
    final update = MediaProgressRules.updateEpisodes(
      current: 0,
      delta: 1,
      total: 12,
      status: MediaWatchStatus.plan,
      now: now,
    );

    expect(update.value, 1);
    expect(update.status, MediaWatchStatus.watching);
    expect(update.lastWatchedAt, now);
    expect(MediaProgressRules.nextEpisode(completed: 1, total: 12), 2);
  });

  test('last episode completes and a later decrement resumes watching', () {
    final completed = MediaProgressRules.updateEpisodes(
      current: 11,
      delta: 1,
      total: 12,
      status: MediaWatchStatus.watching,
      now: now,
    );
    expect(completed.value, 12);
    expect(completed.status, MediaWatchStatus.completed);
    expect(completed.completedAt, now);
    expect(MediaProgressRules.nextEpisode(completed: 12, total: 12), isNull);

    final resumed = MediaProgressRules.updateEpisodes(
      current: 12,
      delta: -1,
      total: 12,
      status: MediaWatchStatus.completed,
      now: now.add(const Duration(minutes: 1)),
    );
    expect(resumed.value, 11);
    expect(resumed.status, MediaWatchStatus.watching);
    expect(resumed.completedAt, isNull);
  });

  test('unknown totals work while invalid episode progress is rejected', () {
    expect(MediaProgressRules.nextEpisode(completed: 8, total: null), 9);
    expect(
      () => MediaProgressRules.updateEpisodes(
        current: 0,
        delta: -1,
        total: null,
        status: MediaWatchStatus.plan,
        now: now,
      ),
      throwsRangeError,
    );
    expect(
      () => MediaProgressRules.updateEpisodes(
        current: 12,
        delta: 1,
        total: 12,
        status: MediaWatchStatus.watching,
        now: now,
      ),
      throwsRangeError,
    );
  });

  test('movie progress validates duration and completes at the end', () {
    final watching = MediaProgressRules.updateMoviePosition(
      positionSeconds: 3600,
      durationSeconds: 7200,
      status: MediaWatchStatus.plan,
      now: now,
    );
    expect(watching.status, MediaWatchStatus.watching);
    expect(watching.value, 3600);

    final completed = MediaProgressRules.updateMoviePosition(
      positionSeconds: 7200,
      durationSeconds: 7200,
      status: MediaWatchStatus.watching,
      now: now,
    );
    expect(completed.status, MediaWatchStatus.completed);
    expect(completed.completedAt, now);

    expect(
      () => MediaProgressRules.updateMoviePosition(
        positionSeconds: 7201,
        durationSeconds: 7200,
        status: MediaWatchStatus.watching,
        now: now,
      ),
      throwsRangeError,
    );
  });

  test('next entry follows custom order and skips completed works', () {
    final next = MediaProgressRules.nextEntryId(
      currentId: 'c',
      entries: const [
        MediaSequenceItem(id: 'a', sortKey: 10, completed: true),
        MediaSequenceItem(id: 'b', sortKey: 20, completed: true),
        MediaSequenceItem(id: 'c', sortKey: 30, completed: false),
        MediaSequenceItem(id: 'd', sortKey: 40, completed: false),
      ],
    );
    expect(next, 'd');
  });
}
