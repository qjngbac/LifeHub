enum MediaCategory {
  tv('TV', '电视剧'),
  anime('ANIME', '动漫'),
  movie('MOVIE', '电影');

  const MediaCategory(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static MediaCategory fromDb(String value) => values.firstWhere(
        (item) => item.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'category'),
      );
}

enum MediaEntryType {
  season('SEASON', '季'),
  movie('MOVIE', '电影 / 剧场版'),
  ova('OVA', 'OVA'),
  ona('ONA', 'ONA'),
  special('SPECIAL', '特别篇'),
  spinOff('SPIN_OFF', '番外'),
  documentary('DOCUMENTARY', '纪录片'),
  other('OTHER', '其他');

  const MediaEntryType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  bool get usesEpisodeProgress => this != movie && this != documentary;

  static MediaEntryType fromDb(String value) => values.firstWhere(
        (item) => item.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'entryType'),
      );
}

enum MediaWatchStatus {
  plan('PLAN', '想看'),
  watching('WATCHING', '在看'),
  completed('COMPLETED', '已看完'),
  paused('PAUSED', '暂停'),
  dropped('DROPPED', '弃剧');

  const MediaWatchStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static MediaWatchStatus fromDb(String value) => values.firstWhere(
        (item) => item.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'watchStatus'),
      );
}

class MediaProgressUpdate {
  const MediaProgressUpdate({
    required this.value,
    required this.status,
    required this.lastWatchedAt,
    required this.completedAt,
  });

  final int value;
  final MediaWatchStatus status;
  final DateTime lastWatchedAt;
  final DateTime? completedAt;
}

class MediaSequenceItem {
  const MediaSequenceItem({
    required this.id,
    required this.sortKey,
    required this.completed,
  });

  final String id;
  final double sortKey;
  final bool completed;
}

abstract final class MediaProgressRules {
  static int? nextEpisode({required int completed, required int? total}) {
    if (completed < 0 || (total != null && (total < 0 || completed > total))) {
      throw RangeError('影视集数进度无效');
    }
    if (total != null && completed >= total) return null;
    return completed + 1;
  }

  static MediaProgressUpdate updateEpisodes({
    required int current,
    required int delta,
    required int? total,
    required MediaWatchStatus status,
    required DateTime now,
  }) {
    final value = current + delta;
    if (value < 0 || total != null && (total < 0 || value > total)) {
      throw RangeError('影视集数进度无效');
    }
    final complete = total != null && value == total;
    return MediaProgressUpdate(
      value: value,
      status: complete
          ? MediaWatchStatus.completed
          : value > 0 || status == MediaWatchStatus.completed
              ? MediaWatchStatus.watching
              : status,
      lastWatchedAt: now,
      completedAt: complete ? now : null,
    );
  }

  static MediaProgressUpdate updateMoviePosition({
    required int positionSeconds,
    required int? durationSeconds,
    required MediaWatchStatus status,
    required DateTime now,
  }) {
    if (positionSeconds < 0 ||
        durationSeconds != null &&
            (durationSeconds < 0 || positionSeconds > durationSeconds)) {
      throw RangeError('影视播放位置无效');
    }
    final complete = durationSeconds != null &&
        durationSeconds > 0 &&
        positionSeconds == durationSeconds;
    return MediaProgressUpdate(
      value: positionSeconds,
      status: complete
          ? MediaWatchStatus.completed
          : positionSeconds > 0 || status == MediaWatchStatus.completed
              ? MediaWatchStatus.watching
              : status,
      lastWatchedAt: now,
      completedAt: complete ? now : null,
    );
  }

  static String? nextEntryId({
    required String currentId,
    required List<MediaSequenceItem> entries,
  }) {
    final ordered = [...entries]
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final index = ordered.indexWhere((item) => item.id == currentId);
    if (index < 0) return null;
    for (final item in ordered.skip(index + 1)) {
      if (!item.completed) return item.id;
    }
    return null;
  }
}
