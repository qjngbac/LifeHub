enum ReadingStatus {
  planned('PLANNED'),
  reading('READING'),
  paused('PAUSED'),
  completed('COMPLETED'),
  dropped('DROPPED');

  const ReadingStatus(this.dbValue);
  final String dbValue;

  static ReadingStatus fromDb(String value) => values.firstWhere(
        (item) => item.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'status'),
      );
}

enum ReadingType { book, novel, comic, paper, other }

enum ReadingUnit { page, chapter, percent }

class ReadingProgressUpdate {
  const ReadingProgressUpdate({
    required this.current,
    required this.status,
    required this.lastReadAt,
    required this.completedAt,
  });

  final int current;
  final ReadingStatus status;
  final DateTime lastReadAt;
  final DateTime? completedAt;
}

abstract final class ReadingProgressRules {
  static double? fraction({required int current, required int? total}) {
    _validate(current: current, total: total);
    if (total == null || total == 0) return null;
    return current / total;
  }

  static ReadingProgressUpdate update({
    required int current,
    required int next,
    required int? total,
    required ReadingStatus status,
    required DateTime now,
  }) {
    _validate(current: next, total: total);
    final complete = total != null && total > 0 && next == total;
    return ReadingProgressUpdate(
      current: next,
      status: complete
          ? ReadingStatus.completed
          : next > 0 || status == ReadingStatus.completed
              ? ReadingStatus.reading
              : status,
      lastReadAt: now,
      completedAt: complete ? now : null,
    );
  }

  static void _validate({required int current, required int? total}) {
    if (current < 0 || total != null && (total < 0 || current > total)) {
      throw RangeError('阅读进度无效');
    }
  }
}
