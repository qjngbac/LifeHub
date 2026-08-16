import 'package:flutter_test/flutter_test.dart';
import 'package:lifehub/core/notifications/v1_9_reminder_rules.dart';

void main() {
  test('subscription reminder dates use local morning and selected lead days',
      () {
    final values = V19ReminderRules.subscriptionTriggers(
      renewalDate: DateTime(2026, 9, 10),
      reminderDays: const [7, 1, 0],
    );

    expect(values, [
      DateTime(2026, 9, 3, 9),
      DateTime(2026, 9, 9, 9),
      DateTime(2026, 9, 10, 9),
    ]);
  });

  test('maintenance expiry and parcel reminders have deterministic timing', () {
    expect(
      V19ReminderRules.maintenanceTrigger(
        nextDueAt: DateTime(2026, 9, 10, 14),
        reminderDays: 2,
      ),
      DateTime(2026, 9, 8, 14),
    );
    expect(
      V19ReminderRules.expiryTrigger(DateTime(2026, 9, 10)),
      DateTime(2026, 9, 3, 9),
    );
    expect(
      V19ReminderRules.parcelTrigger(DateTime(2026, 9, 10, 18)),
      DateTime(2026, 9, 10, 16),
    );
  });

  test('parcel notification text never contains tracking or pickup secrets',
      () {
    final message = V19ReminderRules.parcelMessage(
      title: '书籍快递',
      trackingNumber: 'SF123456789',
      pickupCode: '998877',
    );

    expect(message.title, '有快递需要处理');
    expect(message.body, '请打开 LifeHub 查看待取件信息');
    expect('${message.title}${message.body}', isNot(contains('SF123456789')));
    expect('${message.title}${message.body}', isNot(contains('998877')));
  });
}
