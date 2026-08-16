class NotificationPayload {
  const NotificationPayload({
    required this.type,
    required this.entityId,
    this.notificationId,
  });

  final String type;
  final String entityId;
  final int? notificationId;

  static NotificationPayload? parse(String? raw) {
    if (raw == null) return null;
    final separator = raw.indexOf(':');
    if (separator <= 0 || separator == raw.length - 1) return null;
    final type = raw.substring(0, separator);
    final remainder = raw.substring(separator + 1);
    final idSeparator = remainder.lastIndexOf('|');
    if (idSeparator <= 0 || idSeparator == remainder.length - 1) {
      return NotificationPayload(type: type, entityId: remainder);
    }
    final notificationId = int.tryParse(remainder.substring(idSeparator + 1));
    if (notificationId == null) {
      return NotificationPayload(type: type, entityId: remainder);
    }
    return NotificationPayload(
      type: type,
      entityId: remainder.substring(0, idSeparator),
      notificationId: notificationId,
    );
  }

  String encode() => notificationId == null
      ? '$type:$entityId'
      : '$type:$entityId|$notificationId';
}
