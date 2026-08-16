abstract final class NotificationIds {
  static int forOccurrence(String type, String entityId, int occurrence) {
    const offset = 0x811c9dc5;
    const prime = 0x01000193;
    var hash = offset;
    for (final unit in '$type:$entityId:$occurrence'.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
