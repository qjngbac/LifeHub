abstract final class DepartureRules {
  static DateTime suggestedDepartureAt({
    required DateTime start,
    required int travelMinutes,
    required int preparationMinutes,
  }) {
    if (travelMinutes < 0 || preparationMinutes < 0) {
      throw RangeError('准备时间和路程时间不能为负数');
    }
    return start.subtract(Duration(
      minutes: travelMinutes + preparationMinutes,
    ));
  }
}
