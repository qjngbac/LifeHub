class ConsumableState {
  const ConsumableState({
    required this.lowStock,
    required this.expiringSoon,
    required this.expired,
  });

  final bool lowStock;
  final bool expiringSoon;
  final bool expired;
}

abstract final class ConsumableRules {
  static ConsumableState state({
    required double quantity,
    double? minimumQuantity,
    DateTime? expiryDate,
    required DateTime now,
    int expiringDays = 7,
  }) {
    if (quantity < 0 || (minimumQuantity != null && minimumQuantity < 0)) {
      throw RangeError('库存数量不能为负数');
    }
    if (expiringDays < 0) throw RangeError('临期天数不能为负数');
    final today = DateTime(now.year, now.month, now.day);
    final expiry = expiryDate == null
        ? null
        : DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final expired = expiry?.isBefore(today) ?? false;
    final expiring = expiry != null &&
        !expired &&
        !expiry.isAfter(today.add(Duration(days: expiringDays)));
    return ConsumableState(
      lowStock: minimumQuantity != null && quantity <= minimumQuantity,
      expiringSoon: expiring,
      expired: expired,
    );
  }
}
