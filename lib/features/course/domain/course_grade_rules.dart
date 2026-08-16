class CourseGradeValue {
  const CourseGradeValue({
    required this.score,
    required this.maximum,
    this.weight,
  });

  final double score;
  final double maximum;
  final double? weight;
}

abstract final class CourseGradeRules {
  static void validate({
    required double score,
    required double maximum,
    double? weight,
  }) {
    if (maximum <= 0 || score < 0 || score > maximum) {
      throw RangeError('成绩必须在 0 和满分之间');
    }
    if (weight != null && (weight <= 0 || weight > 1)) {
      throw RangeError('权重必须大于 0 且不超过 1');
    }
  }

  static double? weightedSummary(List<CourseGradeValue> values) {
    if (values.isEmpty || values.any((value) => value.weight == null)) {
      return null;
    }
    for (final value in values) {
      validate(
        score: value.score,
        maximum: value.maximum,
        weight: value.weight,
      );
    }
    final totalWeight = values.fold<double>(
      0,
      (sum, value) => sum + value.weight!,
    );
    if ((totalWeight - 1).abs() > .000001) return null;
    return values.fold<double>(
      0,
      (sum, value) => sum + value.score / value.maximum * 100 * value.weight!,
    );
  }
}
