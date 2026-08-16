class PrivateNotificationMessage {
  const PrivateNotificationMessage({required this.title, required this.body});

  final String title;
  final String body;
}

abstract final class V19ReminderRules {
  static List<DateTime> subscriptionTriggers({
    required DateTime renewalDate,
    required List<int> reminderDays,
  }) =>
      reminderDays
          .where((days) => days >= 0)
          .toSet()
          .map(
            (days) => DateTime(
              renewalDate.year,
              renewalDate.month,
              renewalDate.day,
              9,
            ).subtract(Duration(days: days)),
          )
          .toList()
        ..sort();

  static DateTime maintenanceTrigger({
    required DateTime nextDueAt,
    required int reminderDays,
  }) =>
      nextDueAt.subtract(Duration(days: reminderDays < 0 ? 0 : reminderDays));

  static DateTime expiryTrigger(DateTime expiryDate, {int daysBefore = 7}) =>
      DateTime(expiryDate.year, expiryDate.month, expiryDate.day, 9)
          .subtract(Duration(days: daysBefore < 0 ? 0 : daysBefore));

  static DateTime parcelTrigger(DateTime pickupDeadline) =>
      pickupDeadline.subtract(const Duration(hours: 2));

  static PrivateNotificationMessage parcelMessage({
    required String title,
    String? trackingNumber,
    String? pickupCode,
  }) =>
      const PrivateNotificationMessage(
        title: '有快递需要处理',
        body: '请打开 LifeHub 查看待取件信息',
      );
}
