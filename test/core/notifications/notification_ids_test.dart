import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/notifications/notification_ids.dart';

void main() {
  test('notification ids are stable and distinguish occurrences', () {
    final first = NotificationIds.forOccurrence('EVENT', 'abc', 100);
    expect(first, NotificationIds.forOccurrence('EVENT', 'abc', 100));
    expect(first, isNot(NotificationIds.forOccurrence('EVENT', 'abc', 200)));
    expect(first, inInclusiveRange(1, 0x7fffffff));
  });
}
